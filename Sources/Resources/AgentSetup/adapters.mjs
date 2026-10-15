import { homedir } from 'node:os';
import { promises as fs, constants } from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { parse as parseJSONC, modify, applyEdits } from './vendor/jsonc-parser/lib/esm/main.js';
import { parseDocument } from './vendor/yaml/browser/index.js';

// Native format sources (not a claim that a particular gateway model supports tools):
// Claude: https://code.claude.com/docs/en/llm-gateway-connect
// Picker: https://code.claude.com/docs/en/settings-reference#modelpicker
// Codex: https://developers.openai.com/codex/config-reference
// Profiles: https://developers.openai.com/codex/config-file/config-advanced
// Catalog: https://github.com/openai/codex/blob/main/codex-rs/protocol/src/openai_models.rs
// OpenCode: https://opencode.ai/docs/config/ and https://opencode.ai/docs/providers/#custom-provider
// OMP: https://github.com/can1357/oh-my-pi/blob/main/docs/models.md
// Standard local configs are managed. Confirmed Codex apply activates WikiVibe
// for desktop and CLI; other agents retain their model selections and roles.
const ENDPOINTS = new Set(['https://api.wikivibe.dev/v1', 'https://vapi.wikivibe.dev/v1']);
const BACKUPS = '.wikivibe-gateway-backups';
const AGENTS = [
  { id: 'claude', label: 'Claude Code', rel: '.claude/settings.json' },
  { id: 'codex', label: 'Codex', rel: '.codex/config.toml' },
  { id: 'opencode', label: 'OpenCode', rel: '.config/opencode/opencode.json' },
  { id: 'omp', label: 'oh-my-pi', rel: '.omp/agent/models.yml' },
];
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const own = (object, key) => Object.hasOwn(object, key);
const json = value => `${JSON.stringify(value, null, 2)}\n`;
function fail(message) { throw new Error(message); }
function selected(ids) {
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > AGENTS.length || ids.some(id => typeof id !== 'string' || !AGENTS.some(a => a.id === id))) fail('Выберите поддерживаемых агентов.');
  return [...new Set(ids)].map(id => AGENTS.find(a => a.id === id));
}
function preferences(value, secret = false) {
  if (!value || !ENDPOINTS.has(value.baseUrl)) fail('Недопустимый адрес API WikiVibe.');
  if (!Array.isArray(value.models) || !value.models.length || value.models.some(model => !object(model) || typeof model.id !== 'string' || !model.id.trim() || model.id.length > 300 || /[\x00-\x1f\x7f]/.test(model.id) || model.available === false) || new Set(value.models.map(model => model.id)).size !== value.models.length) fail('Нужен непустой каталог моделей, доступных текущему API-ключу.');
  // OMP resolves !commands, $variables and bare environment names in apiKey.
  // Reject expression-shaped keys rather than letting a consumer execute one.
  if (secret && (typeof value.apiKey !== 'string' || !value.apiKey.trim() || value.apiKey.length > 4096 || /[\s\x00-\x1f\x7f$]/.test(value.apiKey) || value.apiKey.startsWith('!') || /^[A-Z_][A-Z0-9_]*$/.test(value.apiKey))) fail('API-ключ должен содержать само значение ключа, а не команду или имя переменной.');
}
function responseAPI(value, model) {
  const allowed = value.protocols;
  const preferResponses = model.startsWith('gpt-');
  if (!Array.isArray(allowed)) return preferResponses;
  if (preferResponses && allowed.includes('openai_responses')) return true;
  if (allowed.includes('openai_chat_completions')) return false;
  if (allowed.includes('openai_responses')) return true;
  fail('API-ключ не разрешает протокол OpenAI для этого агента.');
}
function isImageModel(id) { return id.startsWith('gpt-image-'); }
function imageConfiguration(value) {
  const responses = !Array.isArray(value.protocols) || value.protocols.includes('openai_responses');
  const carrier = value.models.some(({ id }) => /^gpt-(?:[5-9]|[1-9]\d)(?:[.-]|$)/.test(id));
  return responses && carrier && value.models.some(({ id }) => isImageModel(id));
}
function imagePaths(agent) {
  if (agent.id === 'omp') return [];
  const directory = path.dirname(agent.rel);
  return [`${directory}/wikivibe-images.mjs`, `${directory}/wikivibe-images.json`];
}
function withImagePaths(agent, paths) {
  return [...imagePaths(agent), ...paths, ...(agent.id === 'claude' ? ['.claude.json'] : [])];
}
function imageCommand(agent, root) {
  return { command: process.execPath, args: imagePaths(agent).map(rel => path.join(root, rel)) };
}
function jsonMCP(config, key, agent, value, root, merge, nativeOpenCode = false) {
  const enabled = value.models.some(({ id }) => isImageModel(id));
  if (!enabled && !merge) return;
  if (!enabled && !own(config, key)) return;
  const servers = child(config, key);
  const existing = servers.wikivibe_images;
  const launch = imageCommand(agent, root);
  const ours = existing && (agent.id === 'opencode'
    ? JSON.stringify(existing.command) === JSON.stringify([launch.command, ...launch.args])
    : existing.command === launch.command && JSON.stringify(existing.args) === JSON.stringify(launch.args));
  if (own(servers, 'wikivibe_images') && (!merge || !ours)) fail('Конфликт: MCP wikivibe_images уже существует или изменён; файл не изменён.');
  if (!enabled) { delete servers.wikivibe_images; return; }
  if (merge && !existing) return; // Explicit user removal is not undone.
  servers.wikivibe_images = agent.id === 'opencode'
    ? { type: 'local', command: [launch.command, ...launch.args], ...(nativeOpenCode ? { timeout: { execution: 180000 } } : { enabled: true, timeout: 180000 }), ...existing }
    : { type: 'stdio', ...launch, ...existing };
}
function tomlMCP(text, agent, value, root, merge) {
  const enabled = value.models.some(({ id }) => isImageModel(id));
  if (!enabled && !merge) return text;
  const newline = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text.trimEnd().split(/\r?\n/);
  if (lines.some(line => /^\s*mcp_servers\s*(?:=|\.)/.test(line) || /^\s*\[\s*["']mcp_servers/.test(line))) fail('Сложная структура MCP TOML не изменяется автоматически.');
  const matches = lines.flatMap((line, i) => /^\s*\[\s*mcp_servers\s*\.\s*(?:wikivibe_images(?=\s*[.\]])|["']wikivibe_images["'])/.test(line) ? [i] : []);
  if (matches.length > 1) fail('Неоднозначная структура MCP TOML; файл не изменён.');
  const launch = imageCommand(agent, root);
  const block = ['[mcp_servers.wikivibe_images]', `command = ${JSON.stringify(launch.command)}`, `args = ${JSON.stringify(launch.args)}`, 'tool_timeout_sec = 180'];
  if (!matches.length) return !enabled || merge ? text : `${text.trimEnd()}${newline}${newline}${block.join(newline)}${newline}`;
  const start = matches[0];
  if (!/^\s*\[\s*mcp_servers\s*\.\s*(?:wikivibe_images|["']wikivibe_images["'])\s*\]\s*(?:#.*)?$/.test(lines[start])) fail('Сложная структура MCP TOML не изменяется автоматически.');
  let end = start + 1;
  while (end < lines.length && !/^\s*\[/.test(lines[end])) end++;
  const current = lines.slice(start + 1, end).map(line => line.trim());
  if (!merge || !current.includes(block[1]) || !current.includes(block[2])) fail('Конфликт: MCP wikivibe_images уже существует или изменён; файл не изменён.');
  if (enabled) return text; // Preserve enabled=false, approval rules and timeouts.
  return `${[...lines.slice(0, start), ...lines.slice(end)].join(newline)}${newline}`;
}
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
// Refusal used whenever the plugin may not touch a file the user changed after applying.
function conflict(label) {
  return `${label}: конфликт с изменениями после применения. Восстановление и перезапись запрещены; ваши изменения сохранены.`;
}
function child(parent, key) {
  if (!own(parent, key)) parent[key] = {};
  if (!object(parent[key])) fail('Конфигурация содержит несовместимую структуру.');
  return parent[key];
}
function parseJSON(bytes) {
  if (bytes === null) return {};
  let result;
  try { result = JSON.parse(bytes.toString('utf8')); }
  catch { fail('Поддерживается только корректный JSON без комментариев; файл не изменён.'); }
  if (!object(result)) fail('Корень конфигурации должен быть объектом JSON.');
  return result;
}
function expandAllowlist(config, key, values, remove = false) {
  if (!own(config, key)) return;
  const entries = config[key];
  if (!Array.isArray(entries) || entries.some(item => typeof item !== 'string')) fail(`Поле ${key} должно быть списком строк; файл не изменён.`);
  if (remove) config[key] = entries.filter(item => !values.includes(item));
  else config[key] = [...entries, ...values.filter(item => !entries.includes(item))];
}

function wikiRoute(url) {
  return typeof url === 'string' && /^https:\/\/(?:api|vapi)\.wikivibe\.(?:dev|ru)\/v1\/?$/.test(url);
}
function parseOpenCode(text) {
  const errors = [];
  const config = parseJSONC(text || '{}', errors, { allowTrailingComma: true });
  if (errors.length || !object(config)) fail('OpenCode: некорректный JSON/JSONC; файл не изменён.');
  return config;
}
function openCodeConfig(text, value, agent, root, merge) {
  const config = parseOpenCode(text);
  const providers = child(config, 'provider');
  const existing = Object.entries(providers).filter(([, entry]) => wikiRoute(entry?.options?.baseURL));
  if (!existing.length && own(providers, 'wikivibe')) fail('OpenCode: wikivibe указывает на другой endpoint; файл не изменён.');
  const routes = existing.length ? existing : [['wikivibe', undefined]];
  let output = text || '{}\n';
  const formattingOptions = { insertSpaces: true, tabSize: 2, eol: text.includes('\r\n') ? '\r\n' : '\n' };
  const set = (keys, setting) => { output = applyEdits(output, modify(output, keys, setting, { formattingOptions })); };
  for (const [id, entry] of routes) {
    if (entry && !object(entry.models ?? {})) fail('OpenCode: models должен быть объектом.');
    const models = Object.fromEntries(value.models.map(({ id: model }) => [model, {
      ...entry?.models?.[model],
      name: entry?.models?.[model]?.name ?? model,
      provider: { npm: responseAPI(value, model) ? '@ai-sdk/openai' : '@ai-sdk/openai-compatible' },
      ...(isImageModel(model) ? { tool_call: false, modalities: { input: ['text', 'image'], output: ['image'] }, name: `${model} · image: use wikivibe_images.generate_image` } : {})
    }]));
    set(['provider', id], {
      ...entry,
      npm: '@ai-sdk/openai-compatible',
      name: 'WikiVibe',
      options: { ...entry?.options, baseURL: value.baseUrl, apiKey: value.apiKey },
      models
    });
  }
  for (const [key, remove] of [['enabled_providers', false], ['disabled_providers', true]]) {
    expandAllowlist(config, key, routes.map(([id]) => id), remove);
    if (own(config, key)) set([key], config[key]);
  }
  const nativeMCP = object(config.mcp) && (own(config.mcp, 'timeout') || (own(config.mcp, 'servers') && !config.mcp.servers?.type));
  if (nativeMCP) {
    if (own(config.mcp, 'wikivibe_images')) fail('Конфликт: MCP wikivibe_images одновременно с контейнером OpenCode v2; файл не изменён.');
    jsonMCP(config.mcp, 'servers', agent, value, root, merge, true);
    if (own(config.mcp, 'servers')) set(['mcp', 'servers', 'wikivibe_images'], config.mcp.servers.wikivibe_images);
  } else {
    jsonMCP(config, 'mcp', agent, value, root, merge);
    if (own(config, 'mcp')) set(['mcp', 'wikivibe_images'], config.mcp.wikivibe_images);
  }
  return output;
}
function ompModels(text, value) {
  const document = parseDocument(text, { uniqueKeys: true });
  if (document.errors.length || document.anchors?.size) fail('oh-my-pi: некорректный YAML; файл не изменён.');
  let config;
  try { config = document.toJS({ maxAliasCount: 0 }) ?? {}; }
  catch { fail('oh-my-pi: YAML aliases не поддерживаются.'); }
  const existing = Object.entries(config.providers ?? {}).filter(([, entry]) => wikiRoute(entry?.baseUrl));
  if (existing.length > 1) fail('oh-my-pi: несколько маршрутов WikiVibe; автоматическое изменение неоднозначно.');
  if (!existing.length && own(config.providers ?? {}, 'wikivibe')) fail('oh-my-pi: wikivibe указывает на другой endpoint; файл не изменён.');
  const [id, entry] = existing[0] ?? ['wikivibe', {}];
  if (!Array.isArray(entry.models ?? [])) fail('oh-my-pi: models должен быть массивом.');
  const models = value.models.map(({ id: model }) => ({
    ...entry.models?.find(row => row.id === model),
    id: model,
    api: isImageModel(model) || responseAPI(value, model) ? 'openai-responses' : 'openai-completions',
    kind: model.startsWith('gpt-image-') ? 'image' : 'chat',
    ...(model.startsWith('gpt-image-') ? { supportsTools: false } : {})
  }));
  let output = text;
  for (const [field, setting] of Object.entries({ baseUrl: value.baseUrl, apiKey: value.apiKey, api: 'openai-completions', auth: 'apiKey' })) {
    output = yamlSet(output, ['providers', id, field], [JSON.stringify(setting)]);
  }
  return yamlSet(output, ['providers', id, 'models'], [JSON.stringify(models)]);
}
// A deliberately small YAML editing surface, not a general-purpose YAML parser.
// Traversed mappings must be block maps with plain keys and two-space indentation.
// Unrelated blocks are kept byte-for-byte; aliases/anchors/tags/merge keys and
// document streams are refused because their effective values are ambiguous.
function yamlSet(text, keys, replacement) {
  if (/\t|(^|\n)\s*(?:---|\.\.\.|%|<<:)|(?:^|[\s:[,{])[&*!][A-Za-z_]/m.test(text)) fail('Сложный YAML с якорями, тегами, слиянием, границами документов или табуляцией не изменяется.');
  const newline = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text ? text.split(/\r?\n/) : [];
  if (lines.at(-1) === '') lines.pop();
  function update(start, end, depth, index) {
    const indent = depth * 2;
    const key = keys[index];
    const matches = [];
    for (let i = start; i < end; i++) {
      if (!lines[i].trim() || lines[i].trimStart().startsWith('#')) continue;
      const spaces = lines[i].match(/^ */)[0].length;
      if (spaces < indent) fail('Неподдерживаемые отступы YAML.');
      if (spaces === indent) {
        const entry = lines[i].match(/^ *([A-Za-z_][\w-]*):(?:\s+(.*))?\s*$/);
        if (!entry) fail('Поддерживаются только блочные структуры YAML с простыми ключами.');
        if (entry[1] === key) matches.push(i);
      }
    }
    if (matches.length > 1) fail('Ключ конфигурации повторяется; файл не изменён.');
    let at = matches[0];
    if (at === undefined) {
      const body = keys.slice(index).map((k, offset) => `${' '.repeat(indent + offset * 2)}${k}:`);
      body[body.length - 1] += replacement.length === 1 ? ` ${replacement[0]}` : '';
      if (replacement.length !== 1) body.push(...replacement.map(row => `${' '.repeat(indent + (keys.length - index) * 2)}${row}`));
      lines.splice(end, 0, ...body);
      return;
    }
    let stop = at + 1;
    while (stop < end && (!lines[stop].trim() || lines[stop].trimStart().startsWith('#') || lines[stop].match(/^ */)[0].length > indent)) stop++;
    // Comments/blanks following a value belong to the next sibling, not our key.
    while (stop > at + 1 && (!lines[stop - 1].trim() || lines[stop - 1].trimStart().startsWith('#'))) stop--;
    if (index < keys.length - 1) {
      if (!new RegExp(`^ {${indent}}${key}:\\s*(?:#.*)?$`).test(lines[at])) fail('Нельзя расширить однострочную структуру YAML; файл не изменён.');
      update(at + 1, stop, depth + 1, index + 1);
    } else {
      const prefix = `${' '.repeat(indent)}${key}:`;
      const body = replacement.length === 1 ? [`${prefix} ${replacement[0]}`] : [prefix, ...replacement.map(row => `${' '.repeat(indent + 2)}${row}`)];
      lines.splice(at, stop - at, ...body);
    }
  }
  update(0, lines.length, 0, 0);
  return `${lines.join(newline)}${newline}`;
}
function yamlScalar(value) {
  const text = value.trim();
  if (text.startsWith('"')) {
    const quoted = text.match(/^"(?:[^"\\]|\\.)*"(?=\s*(?:#.*)?$)/)?.[0];
    try { if (quoted) return JSON.parse(quoted); } catch {}
    fail('Сложный YAML со списком моделей не изменяется.');
  }
  if (text.startsWith("'")) {
    const quoted = text.match(/^'(?:[^']|'')*'(?=\s*(?:#.*)?$)/)?.[0];
    if (quoted) return quoted.slice(1, -1).replaceAll("''", "'");
    fail('Сложный YAML со списком моделей не изменяется.');
  }
  const plain = text.replace(/\s+#.*$/, '').trim();
  if (!plain || /[{}[\],]|:\s/.test(plain) || /^(?:null|true|false|~|[-+]?\d+(?:\.\d+)?)$/i.test(plain)) fail('Сложный YAML со списком моделей не изменяется.');
  return plain;
}
function yamlList(text, key) {
  const lines = text.split(/\r?\n/);
  const match = new RegExp(`^${key}:\\s*(.*)$`);
  const matches = lines.flatMap((line, index) => match.test(line) ? [index] : []);
  if (!matches.length) return null;
  if (matches.length !== 1) fail('Ключ конфигурации повторяется; файл не изменён.');
  const at = matches[0];
  const inline = lines[at].match(match)[1].trim().replace(/\s+#.*$/, '').trim();
  if (inline && !inline.startsWith('#')) {
    if (!inline.startsWith('[') || !inline.endsWith(']')) fail(`YAML ${key} должен быть простым списком.`);
    try { const value = JSON.parse(inline); if (Array.isArray(value) && value.every(item => typeof item === 'string')) return value; } catch {}
    const body = inline.slice(1, -1).trim();
    if (/["']/.test(body)) fail(`YAML ${key}: сложный inline список не изменяется.`);
    return body ? body.split(',').map(yamlScalar) : [];
  }
  const result = [];
  for (let i = at + 1; i < lines.length; i++) {
    if (!lines[i].trim() || lines[i].trimStart().startsWith('#')) continue;
    if (/^\S/.test(lines[i]) && !lines[i].startsWith('-')) break;
    if (!/^  -\s+/.test(lines[i])) fail(`YAML ${key}: сложные или path-scoped списки не изменяются.`);
    result.push(yamlScalar(lines[i].replace(/^  -\s+/, '')));
  }
  return result;
}
function addYamlAllowlist(text, models, providerId = 'wikivibe') {
  let next = text;
  for (const [key, values, remove] of [
    ['enabledModels', models.map(({ id }) => `${providerId}/${id}`), false],
    ['enabledProviders', [providerId], false],
    ['disabledProviders', [providerId], true]
  ]) {
    const entries = yamlList(next, key);
    if (entries === null || (!remove && entries.length === 0)) continue;
    const merged = remove ? entries.filter(item => !values.includes(item)) : [...entries, ...values.filter(item => !entries.includes(item))];
    if (JSON.stringify(merged) !== JSON.stringify(entries)) next = yamlSet(next, [key], [JSON.stringify(merged)]);
  }
  return next;
}
function ompConfig(text, value, merge = false, providerId = 'wikivibe') {
  let next = addYamlAllowlist(text, value.models, providerId);
  const image = imageConfiguration(value) ? value.models.find(({ id }) => isImageModel(id)) : undefined;
  if (!image || merge) return next;
  const config = parseDocument(next || '{}', { uniqueKeys: true });
  if (config.errors.length || config.anchors?.size) fail('oh-my-pi: некорректный YAML; файл не изменён.');
  let parsed;
  try { parsed = config.toJS({ maxAliasCount: 0 }) ?? {}; }
  catch { fail('oh-my-pi: YAML aliases не поддерживаются.'); }
  if (!object(parsed)) fail('oh-my-pi: корень конфигурации должен быть отображением.');
  if (own(parsed, 'modelRoles') && !object(parsed.modelRoles)) fail('oh-my-pi: modelRoles должен быть отображением.');
  if (!own(parsed.modelRoles ?? {}, 'image')) next = yamlSet(next, ['modelRoles', 'image'], [JSON.stringify(`${providerId}/${image.id}`)]);
  if (own(parsed, 'generate_image') && !object(parsed.generate_image)) fail('oh-my-pi: generate_image должен быть отображением.');
  if (!own(parsed.generate_image ?? {}, 'enabled')) next = yamlSet(next, ['generate_image', 'enabled'], ['true']);
  return next;
}
function tomlConfig(text, value, root, merge = false) {
  if (text.includes('"""') || text.includes("'''")) fail('Многострочные строки TOML не изменяются автоматически.');
  const newline = text.includes('\r\n') ? '\r\n' : '\n';
  const lines = text ? text.split(/\r?\n/) : [];
  if (lines.at(-1) === '') lines.pop();
  let rootEnd = lines.findIndex(line => /^\s*\[/.test(line));
  if (rootEnd < 0) rootEnd = lines.length;
  for (let i = 0; i < rootEnd; i++) {
    if (/^\s*(?:#|$)/.test(lines[i])) continue;
    if (!/^\s*[A-Za-z_][\w-]*\s*=/.test(lines[i])) fail('Сложные ключи в корне TOML не изменяются автоматически.');
    if (/^\s*model_providers(?:\s*=|\.)/.test(lines[i])) fail('model_providers в однострочной таблице TOML или с точечными ключами не изменяется.');
  }
  const keys = ['model', 'model_provider', 'model_catalog_json', 'profile'];
  const rootLines = lines.slice(0, rootEnd);
  const fields = key => rootLines.filter(line => new RegExp(`^\\s*${key}\\s*=`).test(line));
  if (keys.some(key => fields(key).length > 1)) fail('Повторяющиеся ключи модели TOML; файл не изменён.');
  const stringValue = line => {
    if (!line) return undefined;
    const match = line.match(/^[^=]+=\s*("(?:[^"\\]|\\.)*"|'[^']*')\s*(?:#.*)?$/);
    if (!match) fail('Сложное значение модели или профиля TOML не изменяется автоматически.');
    try { return match[1].startsWith("'") ? match[1].slice(1, -1) : JSON.parse(match[1]); }
    catch { fail('Неподдерживаемая строка модели или профиля TOML; файл не изменён.'); }
  };
  let currentModel = stringValue(fields('model')[0]);
  const profile = stringValue(fields('profile')[0]);
  if (profile !== undefined) {
    for (let start = rootEnd; start < lines.length; start++) {
      const header = lines[start].match(/^\s*\[\s*profiles\s*\.\s*("(?:[^"\\]|\\.)*"|'[^']*'|[\w-]+)\s*\]\s*(?:#.*)?$/);
      if (!header) continue;
      const name = /^["']/.test(header[1]) ? stringValue(`profile = ${header[1]}`) : header[1];
      if (name !== profile) continue;
      let end = start + 1;
      while (end < lines.length && !/^\s*\[/.test(lines[end])) end++;
      const models = lines.slice(start + 1, end).filter(line => /^\s*model\s*=/.test(line));
      if (models.length > 1) fail('Повторяющиеся ключи модели TOML; файл не изменён.');
      currentModel = stringValue(models[0]) ?? currentModel;
    }
  }
  const models = value.models.filter(({ id }) => !id.startsWith('gpt-image-'));
  const settings = { model_catalog_json: path.join(root, '.codex/wikivibe-models.json') };
  if (models.length) {
    settings.model = models.some(({ id }) => id === currentModel) ? currentModel : models[0].id;
    settings.model_provider = 'wikivibe';
  }
  // An image-only catalog must not replace a working text route or profile.
  const updated = models.length ? rootLines.filter(line => !/^\s*profile\s*=/.test(line)) : rootLines.slice();
  for (const [key, setting] of Object.entries(settings)) {
    const index = updated.findIndex(line => new RegExp(`^\\s*${key}\\s*=`).test(line));
    const assignment = `${key} = ${JSON.stringify(setting)}`;
    if (index < 0) updated.push(assignment); else updated[index] = assignment;
  }
  lines.splice(0, rootEnd, ...updated);
  rootEnd = updated.length;
  const matches = [];
  for (let i = rootEnd; i < lines.length; i++) {
    if (/^\s*\[\s*model_providers\s*\.\s*(?:wikivibe(?=\s*(?:\.|\]))|["']wikivibe["'])/.test(lines[i])) matches.push(i);
    if (/^\s*\[\s*["']model_providers/.test(lines[i])) fail('Ключи поставщиков TOML в кавычках не изменяются.');
  }
  if (matches.length > 1) fail('Несколько блоков model_providers.wikivibe в TOML; файл не изменён.');
  if (matches.length) {
    if (!merge) fail('Конфликт: поставщик wikivibe уже существует в TOML.');
    // Only the plugin's provider block and confirmed active routing are changed;
    // unrelated edits must survive key rotation.
    const start = matches[0];
    let end = start + 1;
    while (end < lines.length && !/^\s*\[/.test(lines[end])) end++;
    const block = lines.slice(start, end);
    const field = key => block.find(line => new RegExp(`^\\s*${key}\\s*=`).test(line));
    const name = field('name'), base = field('base_url'), wire = field('wire_api'), token = field('experimental_bearer_token');
    const endpoint = base?.trim().match(/^base_url\s*=\s*"([^"]*)"$/)?.[1];
    if (!name || !base || !wire || !token || !/^name\s*=\s*"WikiVibe"$/.test(name.trim()) || !/^wire_api\s*=\s*"responses"$/.test(wire.trim()) || !ENDPOINTS.has(endpoint)) fail('Конфликт: поставщик wikivibe в TOML не принадлежит плагину; файл не изменён.');
    block[block.indexOf(base)] = `base_url = ${JSON.stringify(value.baseUrl)}`;
    block[block.indexOf(token)] = `experimental_bearer_token = ${JSON.stringify(value.apiKey)}`;
    return `${[...lines.slice(0, start), ...block, ...lines.slice(end)].join(newline)}${newline}`;
  }
  const block = ['[model_providers.wikivibe]', 'name = "WikiVibe"', `base_url = ${JSON.stringify(value.baseUrl)}`, 'wire_api = "responses"', `experimental_bearer_token = ${JSON.stringify(value.apiKey)}`];
  lines.push('', ...block);
  return `${lines.join(newline)}${newline}`;
}

// Exact model presets, checked 2026-10-15; /models alone has no effort metadata.
// GPT: https://github.com/openai/codex/blob/main/codex-rs/models-manager/models.json
// DeepSeek: https://api-docs.deepseek.com/guides/thinking_mode
// Gemini: https://ai.google.dev/gemini-api/docs/generate-content/thinking#thinking-levels
// GLM: https://docs.z.ai/guides/capabilities/thinking
// Provider presets do not prove that WikiVibe forwards reasoning.effort.
const CODEX_REASONING = new Map([
  ['gpt-5.5', ['medium', ['low', 'medium', 'high', 'xhigh']]],
  ['gpt-5.6-luna', ['medium', ['low', 'medium', 'high', 'xhigh', 'max']]],
  ['gpt-5.6-sol', ['low', ['low', 'medium', 'high', 'xhigh', 'max', 'ultra']]],
  ['gpt-5.6-terra', ['medium', ['low', 'medium', 'high', 'xhigh', 'max', 'ultra']]],
  ['gpt-6-astra', ['low', ['low', 'medium', 'high', 'xhigh', 'max', 'ultra']]],
  ['gpt-6-luna', ['medium', ['low', 'medium', 'high', 'xhigh', 'max']]],
  ['gpt-6-sol', ['medium', ['low', 'medium', 'high', 'xhigh', 'max', 'ultra']]],
  ['gpt-6.1-sol', ['low', ['low', 'medium', 'high', 'xhigh', 'max', 'ultra']]],
  ['deepseek/deepseek-v4.1-flash', ['high', ['none', 'low', 'high', 'max']]],
  ['deepseek-v4.1-flash', ['high', ['none', 'low', 'high', 'max']]],
  ['gemini-3.8-flash', ['medium', ['low', 'medium', 'high']]],
  // Preview is retired at Google; retain the gateway ID, never substitute a model.
  ['gemini-3.1-flash-lite-preview', ['minimal', ['minimal', 'low', 'medium', 'high']]],
  ['glm-5.3', ['max', ['low', 'high', 'max']]],
  ['glm-5.3-flash', ['max', ['low', 'high', 'max']]],
]);
const CODEX_EFFORTS = [
  { effort: 'none', description: 'Disable reasoning' },
  { effort: 'minimal', description: 'Minimal reasoning; not guaranteed to be off' },
  { effort: 'low', description: 'Fast responses with lighter reasoning' },
  { effort: 'medium', description: 'Balances speed and reasoning depth for everyday tasks' },
  { effort: 'high', description: 'Greater reasoning depth for complex problems' },
  { effort: 'xhigh', description: 'Extra high reasoning depth for complex problems' },
  { effort: 'max', description: 'Maximum reasoning depth for the hardest problems' },
  { effort: 'ultra', description: 'Maximum reasoning with automatic task delegation' },
];
// Other required ModelInfo fields remain conservative client metadata, not
// claims about gateway tools, image support, prices or context limits.
function codexCatalog(models) {
  return { models: models.map(({ id }, priority) => ({
    slug: id, display_name: `WikiVibe · ${id}`, description: id === 'gemini-3.1-flash-lite-preview'
      ? 'WikiVibe; Google Preview снят с обслуживания, маршрут шлюза и reasoning не проверены.'
      : isImageModel(id) ? 'Image model: keep a text model selected and call MCP wikivibe_images.generate_image with this exact ID. Not a text-conversation model.'
        : 'WikiVibe; совместимость Responses и инструментов не проверена.',
    default_reasoning_level: CODEX_REASONING.get(id)?.[0] ?? null,
    supported_reasoning_levels: CODEX_EFFORTS.filter(({ effort }) => CODEX_REASONING.get(id)?.[1].includes(effort)),
    shell_type: 'shell_command',
    visibility: 'list', supported_in_api: true, priority, availability_nux: null, upgrade: null,
    base_instructions: 'You are a coding assistant running in Codex. Follow the user request and repository instructions, use the available tools to complete the task, preserve unrelated user changes, and report the changes and actual verification performed.',
    support_verbosity: false, default_verbosity: null, apply_patch_tool_type: null,
    supports_reasoning_summary_parameter: false, truncation_policy: { mode: 'bytes', limit: 10000 },
    supports_reasoning_summaries: false, supports_parallel_tool_calls: false,
    experimental_supported_tools: [], input_modalities: ['text']
  })) };
}
function render(agent, rel, bytes, value, root, merge = false, providerId = 'wikivibe', imageMerge = false) {
  const text = bytes?.toString('utf8') ?? '';
  if (rel.endsWith('/wikivibe-images.json')) return json({ ...value, models: value.models.map(({ id }) => id) });
  if (agent.id === 'claude' && rel === '.claude.json') {
    const config = parseJSON(bytes);
    jsonMCP(config, 'mcpServers', agent, value, root, imageMerge);
    return json(config);
  }
  if (agent.id === 'opencode') return openCodeConfig(text, value, agent, root, imageMerge);
  if (agent.id === 'codex') {
    // The catalog is plugin-owned: later edits are never overwritten.
    if (rel.endsWith('wikivibe-models.json')) {
      if (bytes !== null) fail(merge ? conflict(agent.label) : 'Codex: файл wikivibe-models.json уже существует и не принадлежит плагину.');
      return json(codexCatalog(value.models));
    }
    return tomlMCP(tomlConfig(text, value, root, merge), agent, value, root, imageMerge);
  }
  if (agent.id === 'omp') {
    if (/\/config\.ya?ml$/.test(rel)) return ompConfig(text, value, merge, providerId);
    return ompModels(text, value);
  }
  const config = parseJSON(bytes);
  switch (agent.id) {
    case 'claude': {
      const env = child(config, 'env');
      if (own(config, 'apiKeyHelper') || own(env, 'ANTHROPIC_API_KEY') || Object.keys(env).some(key => key.startsWith('CLAUDE_CODE_USE_'))) fail('Claude Code: существующий apiKeyHelper, ANTHROPIC_API_KEY или настройка облачного поставщика конфликтует с WikiVibe; файл не изменён.');
      const picker = child(config, 'modelPicker');
      if (own(picker, 'options') && (!Array.isArray(picker.options) || picker.options.some(row => !object(row) || typeof row.model !== 'string'))) fail('Claude Code: modelPicker.options должен быть массивом моделей.');
      // Merge keeps the user's own picker rows and replaces only plugin-labelled ones.
      const options = (picker.options ?? []).filter(row => !(merge && typeof row.label === 'string' && row.label.startsWith('WikiVibe · ')));
      if (options.some(row => value.models.some(model => model.id === row.model))) fail('Claude Code: модель уже существует в пользовательском modelPicker.');
      picker.options = [...options, ...value.models.map(({ id }) => ({ model: id, label: `WikiVibe · ${id}${isImageModel(id) ? ' · image: use wikivibe_images.generate_image' : ''}` }))];
      picker.replaceBuiltInOptions = true;
      expandAllowlist(config, 'availableModels', value.models.map(({ id }) => id));
      env.ANTHROPIC_BASE_URL = value.baseUrl.slice(0, -3);
      env.ANTHROPIC_AUTH_TOKEN = value.apiKey;
      break;
    }
  }
  return json(config);
}


async function homeRoot(home) {
  const root = await fs.realpath(path.resolve(home));
  const stat = await fs.lstat(root);
  if (!stat.isDirectory() || (process.getuid && stat.uid !== process.getuid())) fail('Домашний каталог недоступен или принадлежит другому пользователю.');
  return root;
}
function checkOwner(stat, directory = false) {
  if ((process.getuid && stat.uid !== process.getuid()) || stat.isSymbolicLink() || (directory ? !stat.isDirectory() || Boolean(stat.mode & 0o022) : !stat.isFile() || stat.nlink !== 1)) fail('Небезопасный путь конфигурации: символическая или жёсткая ссылка, неподходящий владелец, тип файла или права каталога.');
}
async function directories(root, target, create = false) {
  const relative = path.relative(root, target);
  if (relative.startsWith('..') || path.isAbsolute(relative)) fail('Путь выходит за домашний каталог.');
  let current = root;
  for (const part of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    let stat;
    try { stat = await fs.lstat(current); }
    catch (error) {
      if (error.code !== 'ENOENT') throw error;
      if (!create) return false;
      try { await fs.mkdir(current, { mode: 0o700 }); }
      catch (mkdirError) { if (mkdirError.code !== 'EEXIST') throw mkdirError; }
      stat = await fs.lstat(current);
    }
    checkOwner(stat, true);
  }
  return true;
}
async function snapshot(root, target) {
  if (!await directories(root, path.dirname(target))) return null;
  let handle;
  try {
    const before = await fs.lstat(target);
    checkOwner(before);
    handle = await fs.open(target, constants.O_RDONLY | constants.O_NOFOLLOW);
    const stat = await handle.stat();
    checkOwner(stat);
    if (stat.ino !== before.ino || stat.dev !== before.dev || stat.size > 2 * 1024 * 1024) fail('Файл конфигурации изменился во время чтения или превышает 2 МБ.');
    const bytes = await handle.readFile();
    const after = await handle.stat();
    if (stat.size !== after.size || stat.mtimeMs !== after.mtimeMs || stat.ctimeMs !== after.ctimeMs) fail('Файл конфигурации изменился во время чтения.');
    return { bytes, hash: hash(bytes), mode: stat.mode & 0o777, ino: stat.ino, dev: stat.dev };
  } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
  finally { await handle?.close(); }
}
function same(a, b) { return a === null ? b === null : b !== null && a.hash === b.hash && a.mode === b.mode && a.ino === b.ino && a.dev === b.dev; }
async function replace(root, target, bytes, expected, mode = 0o600) {
  await directories(root, path.dirname(target), true);
  const temporary = path.join(path.dirname(target), `.wikivibe-${randomUUID()}.tmp`);
  let handle;
  try {
    handle = await fs.open(temporary, 'wx', mode);
    await handle.writeFile(bytes); await handle.chmod(mode); await handle.sync(); await handle.close(); handle = null;
    if (!same(expected, await snapshot(root, target))) fail('Конфликт: файл или права изменились после чтения; пользовательские изменения сохранены.');
    if (expected === null) {
      // link is exclusive, unlike rename: never overwrite a file created meanwhile.
      await fs.link(temporary, target); await fs.unlink(temporary);
    } else await fs.rename(temporary, target);
  } finally {
    await handle?.close();
    await fs.unlink(temporary).catch(error => { if (error.code !== 'ENOENT') throw error; });
  }
}
function backupPath(root, target) { return path.join(path.dirname(target), BACKUPS, `${path.basename(target)}.json`); }
async function readBackup(root, agent, rel, target) {
  const location = backupPath(root, target);
  const saved = await snapshot(root, location);
  if (!saved) return null;
  if (saved.mode !== 0o600 || (await fs.lstat(path.dirname(location))).mode % 512 !== 0o700) fail('Небезопасные права резервной копии; восстановление остановлено.');
  let record;
  try { record = JSON.parse(saved.bytes.toString('utf8')); }
  catch { fail('Резервная копия повреждена; конфигурация не изменена.'); }
  if (!object(record) || record.version !== 1 || record.agentId !== agent.id || record.rel !== rel || !['active', 'pending', 'restoring'].includes(record.state) || !/^[a-f0-9]{64}$/.test(record.appliedHash) || !(record.original === null || object(record.original))) fail('Резервная копия не принадлежит этому адаптеру.');
  if (record.original !== null && (typeof record.original.base64 !== 'string' || !Number.isInteger(record.original.mode) || record.original.mode < 0 || record.original.mode > 0o777 || hash(Buffer.from(record.original.base64, 'base64')) !== record.original.hash)) fail('Резервная копия повреждена.');
  if (record.state === 'pending' && !/^[a-f0-9]{64}$/.test(record.nextHash)) fail('Резервная копия повреждена.');
  return { location, saved, record };
}
function owned(current, record) {
  if (current?.hash === record.appliedHash && current.mode === 0o600) return true;
  if (record.state === 'restoring') return record.original === null ? current === null : current?.hash === record.original.hash && current.mode === record.original.mode;
  if (record.state !== 'pending') return false;
  if (current?.hash === record.nextHash && current.mode === 0o600) return true;
  return record.original === null ? current === null : current?.hash === record.original.hash && current.mode === record.original.mode;
}
async function nativePaths(root, agent) {
  if (agent.id === 'opencode') {
    const jsonc = '.config/opencode/opencode.jsonc';
    const a = await snapshot(root, path.join(root, agent.rel));
    const b = await snapshot(root, path.join(root, jsonc));
    if (a && b) fail('OpenCode: одновременно существуют opencode.json и opencode.jsonc; устраните неоднозначность.');
    return withImagePaths(agent, [b ? jsonc : agent.rel]);
  }
  if (agent.id === 'codex') return withImagePaths(agent, [agent.rel, '.codex/wikivibe-models.json', '.codex/wikivibe.config.toml']);
  if (agent.id !== 'omp') return withImagePaths(agent, [agent.rel]);
  const result = [];
  for (const name of ['models', 'config']) {
    const yml = `.omp/agent/${name}.yml`, yaml = `.omp/agent/${name}.yaml`;
    const a = await snapshot(root, path.join(root, yml));
    const b = await snapshot(root, path.join(root, yaml));
    if (a && b) fail('oh-my-pi: одновременно существуют файлы .yml и .yaml; устраните неоднозначность вручную.');
    result.push(a ? yml : b ? yaml : yml);
  }
  if (await snapshot(root, path.join(root, '.omp/agent/models.json'))) fail('oh-my-pi: плагин не переносит настройки из устаревшего models.json; используйте штатный формат YAML.');
  return result;
}
async function plans(root, agents, value, restore = false) {
  const result = [];
  const failures = [];
  for (const agent of agents) {
    const agentPlans = [];
    try {
      // Restore looks at both supported YAML spellings, independent of which exists now.
      const rels = restore ? managedPaths(agent) : await nativePaths(root, agent);
      const scriptRel = imagePaths(agent)[0];
      const priorImages = !restore && scriptRel ? await readBackup(root, agent, scriptRel, path.join(root, scriptRel)) : null;
      for (const rel of rels) {
        const target = path.join(root, rel);
        const current = await snapshot(root, target);
        const backup = await readBackup(root, agent, rel, target);
        const exact = backup ? owned(current, backup.record) : false;
        if (restore) {
          if (backup && (!exact || backup.record.preserveEdits)) fail(conflict(agent.label));
          if (backup) agentPlans.push({ agent, rel, target, current, backup });
          continue;
        }
        if (backup && backup.record.state !== 'active') fail('Незавершённая операция: сначала восстановите конфигурацию.');
        // Regenerating from the original removes stale plugin models and legacy
        // defaults, but it would also drop later user edits. When the file is no
        // longer exactly what the plugin wrote, the plan merges into the current
        // file instead: unrelated edits must never block key rotation.
        const merge = Boolean(backup) && (!exact || backup.record.preserveEdits === true);
        if (merge && current === null) fail(`${agent.label}: файл удалён после применения. Восстановите резервную копию или создайте файл заново.`);
        // Migrate the former CLI-only profile, but never remove an unowned or
        // subsequently edited profile. Restore still covers older installations.
        if (agent.id === 'codex' && rel.endsWith('wikivibe.config.toml')) {
          if (backup) {
            if (merge) fail(conflict(agent.label));
            agentPlans.push({ agent, rel, target, current, backup, cleanup: true });
          }
          continue;
        }
        const agentValue = value;
        const imageResource = imagePaths(agent).includes(rel);
        const hasImages = value.models.some(({ id }) => isImageModel(id));
        if (imageResource && current !== null && (!backup || merge) && (hasImages || backup)) fail('Конфликт: файл image-инструмента уже существует или изменён; файл не изменён.');
        if ((imageResource || rel === '.claude.json') && !hasImages) {
          if (backup && !merge) agentPlans.push({ agent, rel, target, current, backup, cleanup: true });
          else if (imageResource || !backup) continue;
          if (!merge) continue;
        }
        const filters = agent.id === 'omp' && /\/config\.ya?ml$/.test(rel);
        const baseline = backup && !merge ? backup.record.original === null ? null : Buffer.from(backup.record.original.base64, 'base64') : current?.bytes ?? null;
        if (filters) {
          const hasFilters = ['enabledModels', 'enabledProviders', 'disabledProviders'].some(key => yamlList(baseline?.toString('utf8') ?? '', key) !== null);
          const hasImageRole = imageConfiguration(value);
          if (!hasFilters && !hasImageRole) { if (backup && !merge) agentPlans.push({ agent, rel, target, current, backup, cleanup: true }); continue; }
        }
        let providerId = 'wikivibe';
        if (agent.id === 'omp') {
          const modelPlan = agentPlans.find(plan => /\/models\.ya?ml$/.test(plan.rel));
          if (modelPlan) {
            const config = parseDocument(modelPlan.bytes.toString('utf8')).toJS({ maxAliasCount: 0 });
            const route = Object.entries(config.providers ?? {}).find(([, entry]) => wikiRoute(entry?.baseUrl));
            if (route) providerId = route[0];
          }
        }
        const bytes = rel.endsWith('/wikivibe-images.mjs')
          ? await fs.readFile(new URL('./image-server.mjs', import.meta.url))
          : Buffer.from(render(agent, rel, baseline, agentValue, root, merge, providerId, merge && Boolean(priorImages)));
        const backupDir = path.dirname(backupPath(root, target));
        if (await directories(root, backupDir) && (await fs.lstat(backupDir)).mode % 512 !== 0o700) fail('Каталог резервных копий должен иметь права 0700.');
        agentPlans.push({ agent, rel, target, current, backup, bytes, filters, merge });
      }
      result.push(...agentPlans);
    } catch (error) {
      // An agent is planned as a whole: one blocked or malformed file keeps its
      // other files untouched, but never voids the rest of the selection.
      failures.push({ agentId: agent.id, message: error instanceof Error ? error.message : 'Операция не выполнена.' });
    }
  }
  return { plans: result, failures };
}

async function restorePlan(root, plan) {
  plan.backup.record.state = 'restoring';
  await replace(root, plan.backup.location, Buffer.from(json(plan.backup.record)), plan.backup.saved);
  plan.backup.saved = await snapshot(root, plan.backup.location);
  const original = plan.backup.record.original;
  if (original === null) {
    if (!same(plan.current, await snapshot(root, plan.target))) fail('Конфликт: файл изменился во время восстановления.');
    if (plan.current) await fs.unlink(plan.target);
  } else await replace(root, plan.target, Buffer.from(original.base64, 'base64'), plan.current, original.mode);
  if (!same(plan.backup.saved, await snapshot(root, plan.backup.location))) fail('Конфликт: резервная копия изменилась во время восстановления.');
  await fs.unlink(plan.backup.location);
}

// One lane per home in this process; the exclusive file also excludes other
// plugin processes. A crash can leave the lock: do not steal a possibly live lock.
const lanes = new Map();
async function mutation(home, operation) {
  const root = await homeRoot(home);
  const previous = lanes.get(root) ?? Promise.resolve();
  const pending = previous.catch(() => {}).then(async () => {
    const lock = path.join(root, '.wikivibe-gateway.lock');
    let handle;
    try {
      try { handle = await fs.open(lock, 'wx', 0o600); }
      catch (error) { if (error.code === 'EEXIST') fail('Другая операция ещё выполняется или после сбоя остался файл блокировки .wikivibe-gateway.lock. Закройте плагин перед ручным удалением этого файла.'); throw error; }
      await handle.writeFile(`${process.pid}\n`);
      return await operation(root);
    } finally { if (handle) { await handle.close(); await fs.unlink(lock); } }
  });
  lanes.set(root, pending);
  try { return await pending; }
  finally { if (lanes.get(root) === pending) lanes.delete(root); }
}

function managedPaths(agent) {
  if (agent.id === 'opencode') return withImagePaths(agent, [agent.rel, '.config/opencode/opencode.jsonc']);
  if (agent.id === 'omp') return ['.omp/agent/models.yml', '.omp/agent/models.yaml', '.omp/agent/config.yml', '.omp/agent/config.yaml'];
  if (agent.id === 'codex') return withImagePaths(agent, [agent.rel, '.codex/wikivibe-models.json', '.codex/wikivibe.config.toml']);
  return withImagePaths(agent, [agent.rel]);
}
export async function previewRestoreAgents(agentIds, { home = homedir() } = {}) {
  const agents = selected(agentIds);
  const root = await homeRoot(home);
  const { plans: changes, failures } = await plans(root, agents, undefined, true);
  return { changes: changes.map(plan => ({ agentId: plan.agent.id, path: plan.target, secretOnDisk: plan.backup.record.original !== null })), failures };
}
export async function previewAgents(agentIds, value, { home = homedir() } = {}) {
  const agents = selected(agentIds); preferences(value, true);
  const root = await homeRoot(home);
  const { plans: changes, failures } = await plans(root, agents, { ...value, apiKey: value.apiKey ?? 'preview-redacted' });
  return { changes: changes.map(plan => ({ agentId: plan.agent.id, path: plan.target, secretOnDisk: !plan.cleanup && !plan.filters && !plan.rel.endsWith('wikivibe-models.json') && !plan.rel.endsWith('wikivibe-images.mjs') })), failures };
}
export async function applyAgents(agentIds, value, { home = homedir() } = {}) {
  const agents = selected(agentIds); preferences(value, true);
  return mutation(home, async root => {
    const { plans: changes, failures } = await plans(root, agents, value);
    const applied = [];
    const blocked = failures.slice();
    for (const plan of changes) {
      if (blocked.some(item => item.agentId === plan.agent.id)) continue;
      try {
        if (plan.cleanup) { await restorePlan(root, plan); applied.push({ agentId: plan.agent.id, path: plan.target }); continue; }
        const location = backupPath(root, plan.target);
        await directories(root, path.dirname(location), true);
        if ((await fs.lstat(path.dirname(location))).mode % 512 !== 0o700) fail('Каталог резервных копий должен иметь права 0700.');
        const original = plan.backup?.record.original ?? (plan.current === null ? null : { base64: plan.current.bytes.toString('base64'), hash: plan.current.hash, mode: plan.current.mode });
        // null is meaningful: reapplying must not turn an originally absent file
        // into an original containing the previously written secret.
        const record = { version: 1, agentId: plan.agent.id, rel: plan.rel, original: plan.backup ? plan.backup.record.original : original, state: 'pending', appliedHash: plan.backup?.record.appliedHash ?? plan.current?.hash ?? hash(Buffer.alloc(0)), nextHash: hash(plan.bytes) };
        if (plan.merge || plan.backup?.record.preserveEdits) record.preserveEdits = true;
        await replace(root, location, Buffer.from(json(record)), plan.backup?.saved ?? null);
        await replace(root, plan.target, plan.bytes, plan.current);
        const saved = await snapshot(root, location);
        record.state = 'active'; record.appliedHash = record.nextHash; delete record.nextHash;
        await replace(root, location, Buffer.from(json(record)), saved);
        applied.push({ agentId: plan.agent.id, path: plan.target });
      } catch (error) {
        // Each file is written on its own; one blocked agent keeps the others working.
        blocked.push({ agentId: plan.agent.id, message: error instanceof Error ? error.message : 'Файл не изменён.' });
      }
    }
    const appliedIds = new Set(applied.map(item => item.agentId));
    return { applied, failures: blocked, outcomes: agents.filter(agent => appliedIds.has(agent.id) && !blocked.some(item => item.agentId === agent.id)).map(agent => ({ agentId: agent.id, modelCount: value.models.length })) };
  });
}
export async function restoreAgents(agentIds, { home = homedir() } = {}) {
  const agents = selected(agentIds);
  return mutation(home, async root => {
    const { plans: changes, failures } = await plans(root, agents, undefined, true);
    const restored = [];
    const blocked = failures.slice();
    for (const plan of changes) {
      try { await restorePlan(root, plan); restored.push({ agentId: plan.agent.id, path: plan.target }); }
      catch (error) { blocked.push({ agentId: plan.agent.id, message: error instanceof Error ? error.message : 'Файл не восстановлен.' }); }
    }
    return { restored, failures: blocked };
  });
}

import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import { createHash } from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import { applyAgents, restoreAgents } from '../Sources/Resources/AgentSetup/adapters.mjs';
import { parseDocument } from '../Sources/Resources/AgentSetup/vendor/yaml/browser/index.js';
import { parse as parseJSONC } from '../Sources/Resources/AgentSetup/vendor/jsonc-parser/lib/esm/main.js';

const ids = ['gpt-image-2', 'gpt-image-2.5', 'gpt-6.1-sol', 'deepseek-v4.1-flash', 'gemini-3.8-flash', 'glm-5.3'];
const value = { apiKey: 'fixture-private-key', baseUrl: 'https://api.wikivibe.dev/v1', models: ids.map(id => ({ id })) };
const directories = { codex: '.codex', opencode: '.config/opencode', claude: '.claude' };
const digest = bytes => createHash('sha256').update(bytes).digest('hex');
async function homeFor(t) {
  const home = await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(), 'wikivibe-native-test-')));
  await fs.chmod(home, 0o700);
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  return home;
}
async function put(home, rel, text) {
  const target = path.join(home, rel);
  await fs.mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
  await fs.writeFile(target, text, { mode: 0o600 });
}
const readJSON = async (home, rel) => JSON.parse(await fs.readFile(path.join(home, rel), 'utf8'));
async function apply(home, selected = ['codex', 'opencode', 'omp', 'claude'], input = value) {
  const result = await applyAgents(selected, input, { home });
  assert.deepEqual(result.failures, []);
  return result;
}
async function legacy(home, agent, rel, applied, original = null) {
  await put(home, rel, applied);
  const record = { version: 1, agentId: agent, rel, state: 'active', appliedHash: digest(applied),
    original: original === null ? null : { base64: Buffer.from(original).toString('base64'), hash: digest(original), mode: 0o600 } };
  await put(home, path.join(path.dirname(rel), '.wikivibe-gateway-backups', path.basename(rel) + '.json'), JSON.stringify(record));
}
async function legacyResources(home, agent) {
  const directory = directories[agent];
  for (const name of ['wikivibe-images.mjs', 'wikivibe-images.json']) await legacy(home, agent, `${directory}/${name}`, 'retired-private-fixture');
  return { command: process.execPath, args: ['wikivibe-images.mjs', 'wikivibe-images.json'].map(name => path.join(home, directory, name)) };
}

test('documented vision models expose image input in Codex, OpenCode and OMP', async t => {
  const home = await homeFor(t);
  await apply(home, ['codex', 'opencode', 'omp']);
  const codex = await readJSON(home, '.codex/wikivibe-models.json');
  const bySlug = new Map(codex.models.map(row => [row.slug, row]));
  assert.deepEqual(bySlug.get('gpt-6.1-sol').input_modalities, ['text', 'image']);
  assert.deepEqual(bySlug.get('gpt-image-2').input_modalities, ['text', 'image']);
  assert.deepEqual(bySlug.get('deepseek-v4.1-flash').input_modalities, ['text']);

  const oc = JSON.parse(await fs.readFile(path.join(home, '.config/opencode/opencode.json'), 'utf8'));
  assert.deepEqual(oc.provider.wikivibe.models['gpt-6.1-sol'].modalities, { input: ['text', 'image'], output: ['text'] });
  assert.deepEqual(oc.provider.wikivibe.models['gpt-image-2'].modalities, { input: ['text', 'image'], output: ['image'] });
  assert.equal(oc.provider.wikivibe.models['gpt-image-2'].tool_call, false);
  assert.equal(oc.provider.wikivibe.models['deepseek-v4.1-flash'].modalities, undefined);

  const omp = parseDocument(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8')).toJS();
  const ompModels = new Map(omp.providers.wikivibe.models.map(row => [row.id, row]));
  assert.deepEqual(ompModels.get('gpt-6.1-sol').input, ['text', 'image']);
  assert.deepEqual(ompModels.get('gpt-image-2').input, ['text', 'image']);
  assert.equal(ompModels.get('gpt-image-2').kind, 'image');
  assert.equal(ompModels.get('deepseek-v4.1-flash').input, undefined);
});

test('native catalogs retain every ID, current image selection and user roles; restore returns exact originals', async t => {
  const home = await homeFor(t);
  const originals = {
    '.codex/config.toml': 'model = "gpt-image-2.5"\nmodel_provider = "wikivibe"\nmodel_reasoning_effort = "none"\n[mcp_servers.user_server]\ncommand = "user-tool"\nenabled = false\n',
    '.config/opencode/opencode.jsonc': '{\n // user comment\n "model":"user/chat","mcp":{"servers":{"user_server":{"type":"local","command":["user-tool"],"disabled":true}}}\n}',
    '.claude/settings.json': '{"model":"user-chat","env":{"USER_SETTING":"keep"}}',
    '.omp/agent/config.yml': 'modelRoles:\n  default: user/chat\n  image: user/image\ngenerate_image:\n  enabled: false\n'
  };
  for (const [rel, text] of Object.entries(originals)) await put(home, rel, text);
  await apply(home);
  const codex = await readJSON(home, '.codex/wikivibe-models.json');
  const oc = parseJSONC(await fs.readFile(path.join(home, '.config/opencode/opencode.jsonc'), 'utf8'));
  const omp = parseDocument(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8')).toJS();
  const claude = await readJSON(home, '.claude/settings.json');
  for (const models of [codex.models.map(row => row.slug), Object.keys(oc.provider.wikivibe.models), omp.providers.wikivibe.models.map(row => row.id), claude.modelPicker.options.map(row => row.model)]) assert.deepEqual(new Set(models), new Set(ids));
  assert.match(await fs.readFile(path.join(home, '.codex/config.toml'), 'utf8'), /model = "gpt-image-2.5"/);
  assert.equal(oc.model, 'user/chat');
  assert.deepEqual(oc.mcp.servers.user_server, parseJSONC(originals['.config/opencode/opencode.jsonc']).mcp.servers.user_server);
  assert.equal(await fs.readFile(path.join(home, '.omp/agent/config.yml'), 'utf8'), originals['.omp/agent/config.yml']);
  for (const model of omp.providers.wikivibe.models.filter(row => row.id.startsWith('gpt-image-'))) {
    assert.equal(model.kind, 'image');
    assert.equal(model.api, 'openai-responses');
  }
  for (const directory of Object.values(directories)) for (const name of ['wikivibe-images.mjs', 'wikivibe-images.json']) await assert.rejects(fs.stat(path.join(home, directory, name)), { code: 'ENOENT' });
  assert.deepEqual((await restoreAgents(['codex', 'opencode', 'omp', 'claude'], { home })).failures, []);
  for (const [rel, text] of Object.entries(originals)) assert.equal(await fs.readFile(path.join(home, rel), 'utf8'), text);
});

test('an image-only catalog does not replace an existing text route or an unrelated identically named MCP', async t => {
  const home = await homeFor(t);
  const original = 'model = "user-chat"\nmodel_provider = "other"\nprofile = "work"\n[mcp_servers.wikivibe_images]\ncommand = "user-owned-tool"\n';
  await put(home, '.codex/config.toml', original);
  await apply(home, ['codex'], { ...value, models: [{ id: 'gpt-image-2' }] });
  const text = await fs.readFile(path.join(home, '.codex/config.toml'), 'utf8');
  for (const line of original.trim().split('\n')) assert.ok(text.split('\n').includes(line));
});

test('retired MCP resources and registrations are removed while later model, project and other-server edits survive', async t => {
  const home = await homeFor(t);
  const codexLaunch = await legacyResources(home, 'codex');
  const codex = `model = "gpt-6.1-sol"\n[mcp_servers.wikivibe_images]\ncommand = ${JSON.stringify(codexLaunch.command)}\nargs = ${JSON.stringify(codexLaunch.args)}\nenabled = false\n[mcp_servers.user_server]\ncommand = "user-tool"\n`;
  await legacy(home, 'codex', '.codex/config.toml', codex, 'model = "user-chat"\n');
  await put(home, '.codex/config.toml', codex.replace('model = "gpt-6.1-sol"', 'model = "gpt-image-2.5"'));
  const ocLaunch = await legacyResources(home, 'opencode');
  const oc = { model: 'user/chat', mcp: { timeout: { startup: 45000 }, servers: { wikivibe_images: { type: 'local', command: [ocLaunch.command, ...ocLaunch.args], disabled: true }, user_server: { type: 'local', command: ['user-tool'] } } } };
  await legacy(home, 'opencode', '.config/opencode/opencode.jsonc', JSON.stringify(oc), '{}');
  await put(home, '.config/opencode/opencode.jsonc', '// retain this comment\n' + JSON.stringify(oc));
  const claudeLaunch = await legacyResources(home, 'claude');
  const claude = { mcpServers: { wikivibe_images: { type: 'stdio', ...claudeLaunch }, user_server: { command: 'user-tool' } } };
  await legacy(home, 'claude', '.claude.json', JSON.stringify(claude), '{"mcpServers":{"user_server":{"command":"user-tool"}}}');
  claude.projects = { '/user/project': { disabledMcpServers: ['external'] } };
  await put(home, '.claude.json', JSON.stringify(claude));
  await apply(home, ['codex', 'opencode', 'claude']);
  const codexAfter = await fs.readFile(path.join(home, '.codex/config.toml'), 'utf8');
  assert.match(codexAfter, /model = "gpt-image-2.5"/);
  assert.equal(codexAfter.includes('mcp_servers.wikivibe_images'), false);
  assert.ok(codexAfter.includes('[mcp_servers.user_server]'));
  const ocText = await fs.readFile(path.join(home, '.config/opencode/opencode.jsonc'), 'utf8');
  const ocAfter = parseJSONC(ocText);
  assert.ok(ocText.includes('// retain this comment'));
  assert.equal(Object.hasOwn(ocAfter.mcp.servers, 'wikivibe_images'), false);
  assert.deepEqual(ocAfter.mcp.servers.user_server, oc.mcp.servers.user_server);
  assert.deepEqual(ocAfter.mcp.timeout, oc.mcp.timeout);
  assert.equal(ocAfter.model, oc.model);
  const claudeAfter = await readJSON(home, '.claude.json');
  assert.deepEqual(claudeAfter.projects, claude.projects);
  assert.deepEqual(claudeAfter.mcpServers, { user_server: { command: 'user-tool' } });
  for (const directory of Object.values(directories)) for (const name of ['wikivibe-images.mjs', 'wikivibe-images.json']) await assert.rejects(fs.stat(path.join(home, directory, name)), { code: 'ENOENT' });
});

test('a user-edited retired script blocks the whole agent instead of deleting user code or its registration', async t => {
  const home = await homeFor(t);
  const launch = await legacyResources(home, 'codex');
  const text = `model = "gpt-image-2.5"\n[mcp_servers.wikivibe_images]\ncommand = ${JSON.stringify(launch.command)}\nargs = ${JSON.stringify(launch.args)}\n`;
  await legacy(home, 'codex', '.codex/config.toml', text, null);
  const edited = 'retired-private-fixture\n// user change\n';
  await put(home, '.codex/wikivibe-images.mjs', edited);
  const result = await applyAgents(['codex'], value, { home });
  assert.deepEqual(result.failures.map(row => row.agentId), ['codex']);
  assert.equal(await fs.readFile(path.join(home, '.codex/config.toml'), 'utf8'), text);
  assert.equal(await fs.readFile(path.join(home, '.codex/wikivibe-images.mjs'), 'utf8'), edited);
});

test('an unedited retired Claude config returns its exact original bytes and removes its backup', async t => {
  const home = await homeFor(t);
  const launch = await legacyResources(home, 'claude');
  const original = '{ "mcpServers": {"user_server":{"command":"user-tool"}}, "theme":"dark" }\n';
  const applied = JSON.parse(original);
  applied.mcpServers.wikivibe_images = { type: 'stdio', ...launch };
  await legacy(home, 'claude', '.claude.json', JSON.stringify(applied), original);
  await apply(home, ['claude']);
  assert.equal(await fs.readFile(path.join(home, '.claude.json'), 'utf8'), original);
  await assert.rejects(fs.stat(path.join(home, '.wikivibe-gateway-backups/.claude.json.json')), { code: 'ENOENT' });
});

test('owned legacy resources never authorize removal of a changed launch command', async t => {
  const home = await homeFor(t);
  await legacyResources(home, 'opencode');
  const original = '{"mcp":{"wikivibe_images":{"type":"local","command":["user-tool"]}}}';
  await legacy(home, 'opencode', '.config/opencode/opencode.json', original, '{}');
  await put(home, '.config/opencode/opencode.json', original + '\n');
  const result = await applyAgents(['opencode'], value, { home });
  assert.deepEqual(result.failures.map(row => row.agentId), ['opencode']);
  assert.equal(await fs.readFile(path.join(home, '.config/opencode/opencode.json'), 'utf8'), original + '\n');
  assert.equal(await fs.readFile(path.join(home, '.config/opencode/wikivibe-images.mjs'), 'utf8'), 'retired-private-fixture');
});

test('user-deleted created legacy files remain absent and their backup records retire', async t => {
  const home = await homeFor(t);
  await legacyResources(home, 'claude');
  await legacy(home, 'claude', '.claude.json', '{"mcpServers":{}}');
  for (const rel of ['.claude/wikivibe-images.mjs', '.claude/wikivibe-images.json', '.claude.json']) await fs.unlink(path.join(home, rel));
  await apply(home, ['claude']);
  for (const rel of ['.claude/wikivibe-images.mjs', '.claude/wikivibe-images.json', '.claude.json', '.claude/.wikivibe-gateway-backups/wikivibe-images.mjs.json']) await assert.rejects(fs.stat(path.join(home, rel)), { code: 'ENOENT' });
});

test('provider image type selects the native IMAGE role without guessing from its ID', async t => {
  const home = await homeFor(t);
  await apply(home, ['omp'], { ...value, models: [{ id: 'provider-art-model', type: 'image' }] });
  const config = parseDocument(await fs.readFile(path.join(home, '.omp/agent/config.yml'), 'utf8')).toJS();
  const catalog = parseDocument(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8')).toJS();
  assert.equal(config.modelRoles.image, 'wikivibe/provider-art-model');
  assert.equal(catalog.providers.wikivibe.models[0].kind, 'image');
  assert.equal(catalog.providers.wikivibe.models[0].api, 'openai-responses');
});

test('context choices stay model-local, preserve output limits and restore the original baseline', async t => {
  const home = await homeFor(t);
  await put(home, '.config/opencode/opencode.json', JSON.stringify({ provider: { wikivibe: {
    npm: '@ai-sdk/openai-compatible', options: { baseURL: value.baseUrl, apiKey: value.apiKey },
    models: { 'gpt-6.1-sol': { limit: { context: 128000, output: 8192 } } }
  } } }));
  const input = { ...value, models: [{ id: 'gpt-6.1-sol', contextWindow: 1_050_000 }, { id: 'glm-5.3', contextWindow: 3_000_000 }] };
  await apply(home, ['codex', 'opencode', 'omp'], input);
  const oc = (await readJSON(home, '.config/opencode/opencode.json')).provider.wikivibe.models;
  assert.deepEqual(oc['gpt-6.1-sol'].limit, { context: 1_050_000, output: 8192 });
  assert.equal(oc['glm-5.3'].limit.context, 3_000_000);
  const codex = await readJSON(home, '.codex/wikivibe-models.json');
  assert.equal(codex.models.find(row => row.slug === 'gpt-6.1-sol').context_window, 1_050_000);
  assert.equal(codex.models.find(row => row.slug === 'glm-5.3').context_window, 3_000_000);
  const omp = parseDocument(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8')).toJS();
  assert.equal(omp.providers.wikivibe.models.find(row => row.id === 'glm-5.3').contextWindow, 3_000_000);
  await apply(home, ['opencode'], { ...value, models: input.models.map(({ id }) => ({ id })) });
  const reset = (await readJSON(home, '.config/opencode/opencode.json')).provider.wikivibe.models;
  assert.deepEqual(reset['gpt-6.1-sol'].limit, { context: 128000, output: 8192 });
  assert.equal(reset['glm-5.3'].limit?.context, undefined);
});

test('no context override preserves a later manual context edit', async t => {
  const home = await homeFor(t);
  await apply(home, ['opencode'], { ...value, models: [{ id: 'gpt-6.1-sol', contextWindow: 1_000_000 }] });
  const config = await readJSON(home, '.config/opencode/opencode.json');
  config.provider.wikivibe.models['gpt-6.1-sol'].limit = { context: 777777, output: 4096 };
  await put(home, '.config/opencode/opencode.json', JSON.stringify(config));
  await apply(home, ['opencode'], { ...value, models: [{ id: 'gpt-6.1-sol' }] });
  assert.deepEqual((await readJSON(home, '.config/opencode/opencode.json')).provider.wikivibe.models['gpt-6.1-sol'].limit,
    { context: 777777, output: 4096 });
});

test('deeply nested YAML is refused without replacing the agent configuration', async t => {
  const home = await homeFor(t);
  const source = 'providers: ' + '['.repeat(15000) + '1' + ']'.repeat(15000) + '\n';
  await put(home, '.omp/agent/models.yml', source);
  const document = parseDocument(source);
  assert.ok(document.errors.some(error => error.code === 'RESOURCE_EXHAUSTION'));
  const result = await applyAgents(['omp'], value, { home });
  assert.equal(result.failures[0]?.agentId, 'omp');
  assert.deepEqual(result.applied, []);
  assert.equal(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8'), source);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { applyAgents, restoreAgents } from '../Sources/Resources/AgentSetup/adapters.mjs';
import { imageTools } from '../Sources/Resources/AgentSetup/image-server.mjs';
import { parseDocument } from '../Sources/Resources/AgentSetup/vendor/yaml/browser/index.js';
import { parse as parseJSONC, modify, applyEdits } from '../Sources/Resources/AgentSetup/vendor/jsonc-parser/lib/esm/main.js';

const agents = ['codex', 'omp', 'opencode', 'claude'];
const directories = { codex: '.codex', opencode: '.config/opencode', claude: '.claude' };
const ids = ['gpt-image-2', 'gpt-image-2.5', 'gpt-6.1-sol', 'deepseek-v4.1-flash', 'gemini-3.8-flash', 'glm-5.3', 'unknown-provider-model'];
const value = { apiKey: 'fixture-private-key', baseUrl: 'https://api.wikivibe.dev/v1', models: ids.map(id => ({ id })) };
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=';
const readJSON = async (home, rel) => JSON.parse(await fs.readFile(path.join(home, rel), 'utf8'));
async function homeFor(t) {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), 'wikivibe-image-test-'));
  await fs.chmod(home, 0o700);
  t.after(() => fs.rm(home, { recursive: true, force: true }));
  return home;
}
async function put(home, rel, content) {
  const target = path.join(home, rel);
  await fs.mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
  await fs.writeFile(target, typeof content === 'string' ? content : JSON.stringify(content), { mode: 0o600 });
}
async function apply(home, input = value, selected = agents) {
  const result = await applyAgents(selected, input, { home });
  assert.deepEqual(result.failures, []);
  return result;
}
async function catalog(home, agent) {
  if (agent === 'codex') return (await readJSON(home, '.codex/wikivibe-models.json')).models.map(model => model.slug);
  if (agent === 'claude') return (await readJSON(home, '.claude/settings.json')).modelPicker.options.filter(model => model.label.startsWith('WikiVibe · ')).map(model => model.model);
  if (agent === 'opencode') return Object.keys((await readJSON(home, '.config/opencode/opencode.json')).provider.wikivibe.models);
  return parseDocument(await fs.readFile(path.join(home, '.omp/agent/models.yml'), 'utf8')).toJS().providers.wikivibe.models.map(model => model.id);
}

test('every agent retains the exact catalog; user routes, roles and byte-exact originals survive restore', async t => {
  const home = await homeFor(t);
  const originals = {
    '.config/opencode/opencode.json': '{"model":"user/chat","mcp":{"user_server":{"type":"local","command":["user-tool"],"enabled":false}}}',
    '.claude/settings.json': '{"model":"user-chat","env":{"USER_SETTING":"keep"}}',
    '.claude.json': '{"projects":{"/user/project":{"disabledMcpServers":["external"]}},"mcpServers":{"user_server":{"command":"user-tool"}}}',
    '.codex/config.toml': 'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "ultra"\n[mcp_servers.user_server]\ncommand = "user-tool"\nenabled = false\n',
    '.omp/agent/config.yml': 'modelRoles:\n  image: user/image\ngenerate_image:\n  enabled: false\n'
  };
  for (const [rel, text] of Object.entries(originals)) await put(home, rel, text);
  await apply(home);
  for (const agent of agents) assert.deepEqual(new Set(await catalog(home, agent)), new Set(ids), agent);
  assert.equal((await readJSON(home, '.config/opencode/opencode.json')).model, 'user/chat');
  assert.equal((await readJSON(home, '.claude/settings.json')).model, 'user-chat');
  assert.equal(await fs.readFile(path.join(home, '.omp/agent/config.yml'), 'utf8'), originals['.omp/agent/config.yml']);
  const rotated = { ...value, apiKey: 'fixture-rotated-key' };
  await apply(home, rotated, ['codex']);
  for (const agent of Object.keys(directories)) {
    const config = await readJSON(home, `${directories[agent]}/wikivibe-images.json`);
    assert.equal(config.apiKey, agent === 'codex' ? rotated.apiKey : value.apiKey, 'keys are isolated by agent');
  }
  assert.deepEqual((await restoreAgents(agents, { home })).failures, []);
  for (const [rel, text] of Object.entries(originals)) assert.equal(await fs.readFile(path.join(home, rel), 'utf8'), text, rel);
  for (const directory of Object.values(directories)) for (const name of ['wikivibe-images.mjs', 'wikivibe-images.json']) {
    await assert.rejects(fs.stat(path.join(home, directory, name)), { code: 'ENOENT' });
  }
});

test('OpenCode v2 preserves JSONC, other servers, native disabled policy and explicit removal', async t => {
  const home = await homeFor(t);
  const rel = '.config/opencode/opencode.jsonc';
  const original = '{\n  // Keep the user route and MCP policy.\n  "model": "user/chat",\n  "mcp": {\n    "timeout": {"startup": 45000},\n    "servers": {\n      // This server is not managed by WikiVibe.\n      "user_server": {"type":"local","command":["user-tool"],"disabled":true}\n    }\n  }\n}\n';
  await put(home, rel, original);
  await apply(home, value, ['opencode']);
  const read = async () => parseJSONC(await fs.readFile(path.join(home, rel), 'utf8'));
  let config = await read();
  assert.equal(config.model, 'user/chat');
  assert.deepEqual(config.mcp.servers.user_server, parseJSONC(original).mcp.servers.user_server);
  assert.deepEqual(new Set(Object.keys(config.provider.wikivibe.models)), new Set(ids));
  assert.ok(config.mcp.servers.wikivibe_images.command.includes(path.join(await fs.realpath(home), '.config/opencode/wikivibe-images.mjs')));
  assert.equal(Object.hasOwn(config.mcp, 'wikivibe_images'), false);
  const editServer = async server => {
    const text = await fs.readFile(path.join(home, rel), 'utf8');
    await put(home, rel, applyEdits(text, modify(text, ['mcp', 'servers', 'wikivibe_images'], server, {})));
  };
  const userServer = { ...config.mcp.servers.wikivibe_images, disabled: true, codemode: false, timeout: { startup: 32000, execution: 270000 } };
  await editServer(userServer);
  await apply(home, { ...value, apiKey: 'fixture-rotated-key' }, ['opencode']);
  config = await read();
  assert.deepEqual(config.mcp.servers.wikivibe_images, userServer);
  assert.deepEqual(config.mcp.timeout, { startup: 45000 });
  assert.ok((await fs.readFile(path.join(home, rel), 'utf8')).includes('// This server is not managed by WikiVibe.'));
  await editServer(undefined);
  await apply(home, value, ['opencode']);
  assert.equal(Object.hasOwn((await read()).mcp.servers, 'wikivibe_images'), false);
  const edited = await fs.readFile(path.join(home, rel), 'utf8');
  assert.deepEqual((await restoreAgents(['opencode'], { home })).failures.map(failure => failure.agentId), ['opencode']);
  assert.equal(await fs.readFile(path.join(home, rel), 'utf8'), edited);
});

test('protocol and carrier restrictions never remove IDs or send an unusable image request', async t => {
  for (const [models, protocols, selected] of [
    [ids, ['openai_chat_completions'], ['omp', 'opencode']],
    [ids, ['anthropic_messages'], ['claude']],
    [['gpt-image-2', 'other-chat'], ['openai_responses'], ['omp', 'opencode', 'codex']]
  ]) {
    const home = await homeFor(t);
    await apply(home, { ...value, models: models.map(id => ({ id })), protocols }, selected);
    for (const agent of selected) assert.deepEqual(new Set(await catalog(home, agent)), new Set(models), agent);
    if (selected.includes('omp')) await assert.rejects(fs.stat(path.join(home, '.omp/agent/config.yml')), { code: 'ENOENT' });
    let requests = 0;
    const api = imageTools({ ...value, models, protocols }, async () => { requests++; throw new Error('must not reach network'); });
    await assert.rejects(api.call('generate_image', { model: 'gpt-image-2', prompt: 'fixture' }), /Responses|carrier/);
    assert.equal(requests, 0);
  }
});

test('an image-only Codex catalog preserves the existing text provider, model and profile', async t => {
  const home = await homeFor(t);
  const original = 'model = "user-chat"\nmodel_provider = "other"\nprofile = "work"\n[profiles.work]\nmodel = "work-chat"\n';
  await put(home, '.codex/config.toml', original);
  await apply(home, { ...value, models: [{ id: 'gpt-image-2' }] }, ['codex']);
  assert.deepEqual(await catalog(home, 'codex'), ['gpt-image-2']);
  const text = await fs.readFile(path.join(home, '.codex/config.toml'), 'utf8');
  for (const line of original.trim().split('\n')) assert.ok(text.split('\n').includes(line));
});

test('adding image tools to earlier managed configs preserves edits; subsequent disable/removal is respected', async t => {
  const home = await homeFor(t);
  await apply(home, { ...value, models: [{ id: 'gpt-6.1-sol' }] });
  const opencodePath = '.config/opencode/opencode.json';
  let opencode = await readJSON(home, opencodePath);
  opencode.model = 'user/new-chat';
  await put(home, opencodePath, opencode);
  await apply(home);
  opencode = await readJSON(home, opencodePath);
  assert.equal(opencode.model, 'user/new-chat');
  assert.equal(opencode.mcp.wikivibe_images.type, 'local');
  opencode.mcp.wikivibe_images.enabled = false;
  await put(home, opencodePath, opencode);
  const claude = await readJSON(home, '.claude.json');
  delete claude.mcpServers.wikivibe_images;
  claude.projects = { '/user/new-project': { disabledMcpServers: ['external'] } };
  await put(home, '.claude.json', claude);
  const codexPath = path.join(home, '.codex/config.toml');
  await fs.appendFile(codexPath, 'enabled = false\n');
  await apply(home, { ...value, apiKey: 'fixture-rotated-key' });
  assert.equal((await readJSON(home, opencodePath)).mcp.wikivibe_images.enabled, false);
  assert.deepEqual(await readJSON(home, '.claude.json'), claude);
  assert.ok((await fs.readFile(codexPath, 'utf8')).includes('enabled = false'));
  const restore = await restoreAgents(agents, { home });
  assert.deepEqual(new Set(restore.failures.map(row => row.agentId)), new Set(['codex', 'opencode', 'claude']));
  for (const directory of Object.values(directories)) assert.equal((await readJSON(home, `${directory}/wikivibe-images.json`)).apiKey, 'fixture-rotated-key');
});

test('changed image-server code blocks its entire agent; removing images cleans up owned resources', async t => {
  const home = await homeFor(t);
  await apply(home);
  const original = await fs.readFile(path.join(home, '.codex/config.toml'));
  await fs.appendFile(path.join(home, '.codex/wikivibe-images.mjs'), '\n// user change\n');
  const changed = await applyAgents(['codex', 'opencode'], { ...value, apiKey: 'fixture-rotated-key' }, { home });
  assert.deepEqual(changed.failures.map(row => row.agentId), ['codex']);
  assert.deepEqual(await fs.readFile(path.join(home, '.codex/config.toml')), original);
  await apply(home, { ...value, models: [{ id: 'gpt-6.1-sol' }] }, ['opencode', 'claude']);
  for (const directory of [directories.opencode, directories.claude]) for (const name of ['wikivibe-images.mjs', 'wikivibe-images.json']) await assert.rejects(fs.stat(path.join(home, directory, name)), { code: 'ENOENT' });
  assert.equal((await readJSON(home, '.config/opencode/opencode.json')).mcp, undefined);
  await assert.rejects(fs.stat(path.join(home, '.claude.json')), { code: 'ENOENT' });
});

test('completed image output becomes an exact private PNG asset and MCP image content', async t => {
  const api = imageTools({ ...value, models: ids }, async () => Response.json({ status: 'completed', output: [{ type: 'image_generation_call', status: 'completed', model: 'gpt-image-2.5', result: png }] }));
  const result = await api.call('generate_image', { model: 'gpt-image-2.5', carrier_model: 'gpt-6.1-sol', prompt: 'fixture' });
  const metadata = JSON.parse(result.content[0].text);
  const filename = metadata.imagePaths[0];
  t.after(() => fs.rm(path.dirname(filename), { recursive: true, force: true }));
  assert.deepEqual(await fs.readFile(filename), Buffer.from(png, 'base64'));
  assert.equal((await fs.stat(filename)).mode & 0o777, 0o600);
  assert.equal((await fs.stat(path.dirname(filename))).mode & 0o777, 0o700);
  assert.deepEqual(result.content[1], { type: 'image', mimeType: 'image/png', data: png });
});

test('a gateway size mismatch reports actual dimensions and preserves the paid result without resize or retry', async t => {
  let requests = 0;
  const api = imageTools({ ...value, models: ids }, async () => {
    requests++;
    return Response.json({ status: 'completed', output: [{ type: 'image_generation_call', status: 'completed', result: png }] });
  });
  const result = await api.call('generate_image', { model: 'gpt-image-2', prompt: 'fixture', size: '1024x1024' });
  const metadata = JSON.parse(result.content[0].text);
  t.after(() => fs.rm(path.dirname(metadata.imagePaths[0]), { recursive: true, force: true }));
  assert.equal(metadata.sizeMismatch, true);
  assert.deepEqual(metadata.images, [{ path: metadata.imagePaths[0], width: 1, height: 1 }]);
  assert.deepEqual(await fs.readFile(metadata.imagePaths[0]), Buffer.from(png, 'base64'));
  assert.equal(requests, 1);
});

test('upstream failure, URL-only output and malformed images cannot masquerade as success or trigger paid retries', async () => {
  for (const makeResponse of [
    () => new Response(`upstream echoed ${value.apiKey}`, { status: 400 }),
    () => Response.json({ status: 'incomplete', output: [] }),
    () => Response.json({ status: 'completed', output: [{ type: 'message', content: [{ text: 'done' }] }] }),
    ...[
      { status: 'in_progress', result: png },
      { status: 'completed', result: 'https://internal.example/image.png' },
      { status: 'completed', result: Buffer.from('not a PNG').toString('base64') },
      { status: 'completed', result: png, model: 'gpt-image-different' }
    ].map(item => () => Response.json({ status: 'completed', output: [{ type: 'image_generation_call', ...item }] }))
  ]) {
    let requests = 0;
    const api = imageTools({ ...value, models: ids }, async () => { requests++; return makeResponse(); });
    await assert.rejects(api.call('generate_image', { model: 'gpt-image-2', prompt: 'fixture' }), error => {
      assert.equal(error.message.includes(value.apiKey), false);
      assert.equal(error.message.includes('internal.example'), false);
      return true;
    });
    assert.equal(requests, 1, 'no model fallback, URL download or paid retry');
  }
});

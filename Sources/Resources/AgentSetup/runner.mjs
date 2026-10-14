import { previewAgents, previewRestoreAgents, applyAgents, restoreAgents } from './adapters.mjs';
import { promises as fs, constants } from 'node:fs';
import { createHash } from 'node:crypto';

// One request per process. Secrets enter only on stdin; stdout is an allowlisted
// metadata response. Never return raw exceptions or configuration contents.
function reason(error) {
  const text = String(error?.message ?? error ?? '');
  if (/блокировки|Другая операция/.test(text)) return 'locked';
  if (/Небезопас|права|прав каталог|символическ|владел/.test(text)) return 'unsafePath';
  if (/конфликт|Конфликт|изменил|изменён|уже существ|не принадлежит|Не заверш|Незаверш/.test(text)) return 'conflict';
  if (/JSON|YAML|TOML|структур|формат|aliases|коррект|одновременно/.test(text)) return 'invalidConfiguration';
  return 'setupFailed';
}
function safeFailures(failures) {
  return failures.map(row => ({ agentId: row.agentId, error: reason(row.message) }));
}
async function fingerprint(preview, request) {
  const value = request.value ? {
    apiKey: request.value.apiKey,
    baseUrl: request.value.baseUrl,
    models: request.value.models.map(model => typeof model === 'string' ? model : model.id),
    protocols: request.value.protocols ?? null,
  } : null;
  const operation = request.operation === 'previewRestore' || request.operation === 'restore' ? 'restore' : 'apply';
  const hash = createHash('sha256').update(JSON.stringify({ agentIds: request.agentIds, operation, value }));
  for (const row of preview.changes) {
    hash.update(row.path);
    let file;
    try {
      file = await fs.open(row.path, constants.O_RDONLY | constants.O_NOFOLLOW);
      const stat = await file.stat();
      if (!stat.isFile() || stat.nlink !== 1 || stat.size > 2 * 1024 * 1024) throw new Error('Небезопасный путь');
      hash.update(`${stat.mode}:${stat.ino}:${stat.dev}:`).update(await file.readFile());
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      hash.update('absent');
    } finally { await file?.close(); }
  }
  return hash.digest('hex');
}
async function run(request) {
  if (Number(process.versions.node.split('.')[0]) < 22) return { ok: false, error: 'nodeMissing' };
  const allowedAgents = ['codex', 'omp', 'opencode', 'claude'];
  if (!request || !Array.isArray(request.agentIds) || !request.agentIds.length || request.agentIds.some(id => !allowedAgents.includes(id))) throw new Error('Некорректный формат');
  if (!['preview', 'apply', 'previewRestore', 'restore'].includes(request.operation)) throw new Error('Некорректный формат');
  const restoring = ['previewRestore', 'restore'].includes(request.operation);
  if (!restoring) {
    const protocols = request.value?.protocols;
    if (protocols != null && (!Array.isArray(protocols) || protocols.some(p => typeof p !== 'string'))) throw new Error('Некорректный формат');
    if (protocols != null && request.agentIds.some(id => id === 'codex' ? !protocols.includes('openai_responses') : id === 'claude' ? !protocols.includes('anthropic_messages') : !protocols.some(p => ['openai_responses', 'openai_chat_completions'].includes(p)))) throw new Error('Некорректный протокол');
  }
  const preview = restoring ? await previewRestoreAgents(request.agentIds) : await previewAgents(request.agentIds, request.value);
  const stamp = await fingerprint(preview, request);
  if (request.operation.startsWith('preview')) {
    return { ok: true, changes: preview.changes, failures: safeFailures(preview.failures), fingerprint: stamp };
  }
  if (request.fingerprint !== stamp) return { ok: false, error: 'conflict' };
  const result = restoring ? await restoreAgents(request.agentIds) : await applyAgents(request.agentIds, request.value);
  return { ok: true, changes: result.applied ?? result.restored, failures: safeFailures(result.failures) };
}
try {
  let text = '';
  for await (const chunk of process.stdin) {
    text += chunk;
    if (Buffer.byteLength(text) > 2 * 1024 * 1024) throw new Error('Некорректный формат');
  }
  const request = JSON.parse(text);
  process.stdout.write(JSON.stringify(await run(request)));
} catch (error) {
  process.stdout.write(JSON.stringify({ ok: false, error: reason(error) }));
}

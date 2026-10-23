#!/usr/bin/env node
// WikiVibe image generation for Codex.
//
// An MCP server that calls the WikiVibe Responses API with an image model and
// returns the generated PNG both as an image block (so the client can render it
// inline) and as a saved file path. It uses the same WikiVibe provider entry
// that Codex already holds, so no second credential is stored.
//
// Registered by WikiVibe as `[mcp_servers.wikivibe_images]`.
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { homedir, tmpdir } from 'node:os';
import path from 'node:path';

const PROTOCOL_VERSIONS = ['2025-06-18', '2025-03-26', '2024-11-05'];
const DEFAULT_MODEL = 'gpt-image-2.5';
const MAX_BYTES = 32 * 1024 * 1024;
const REQUEST_TIMEOUT_MS = 300_000;
// Codex replaces an oversized MCP result with its own JSON text, so the inline
// image has to stay well under its budget. The full-resolution PNG is still
// written to disk; the chat gets a downscaled preview.
const PREVIEW_EDGE = 900;
const PREVIEW_FORMAT_OPTIONS = '65';
const INLINE_BUDGET = 700_000;
const run = promisify(execFile);

const tool = {
  name: 'generate_image',
  title: 'Generate an image with WikiVibe',
  description:
    'Generate or edit a raster image with WikiVibe. Returns the absolute path of the saved PNG. ' +
    'Use it whenever the user asks for a picture, illustration, logo concept, mockup or diagram artwork. ' +
    'The image is produced by a WikiVibe image model; the prompt is sent to the WikiVibe gateway. ' +
    'IMPORTANT: this is the only image tool that works here. The result already displays the picture ' +
    'in the chat, so reply in one short sentence and do not call view_image or any other image tool. ' +
    'Do not invent a path and do not claim the image exists without the Saved: line.',
  inputSchema: {
    type: 'object',
    properties: {
      prompt: { type: 'string', description: 'What to draw. Be specific about subject, style, lighting and composition.' },
      model: { type: 'string', description: `WikiVibe image model ID. Defaults to ${DEFAULT_MODEL}.` },
      size: { type: 'string', description: 'Optional size such as 1024x1024, 1536x1024 or 1024x1536.' },
      quality: { type: 'string', description: 'Optional quality: low, medium or high.' },
      output_path: { type: 'string', description: 'Optional absolute path for the PNG. Defaults to ~/.codex/generated_images.' }
    },
    required: ['prompt'],
    additionalProperties: false
  }
};

function providerFromConfig(text) {
  const blocks = text.split(/^\[/m);
  const block = blocks.find(chunk => /^model_providers\.wikivibe(?:\.[^\]]*)?\]/.test(chunk));
  if (!block) return null;
  const token = block.match(/experimental_bearer_token\s*=\s*"((?:[^"\\]|\\.)*)"/)?.[1];
  const baseUrl = block.match(/base_url\s*=\s*"([^"]+)"/)?.[1];
  if (!token || !baseUrl) return null;
  return { token: JSON.parse(`"${token}"`), baseUrl: baseUrl.replace(/\/+$/, '') };
}

async function provider() {
  if (process.env.WIKIVIBE_API_KEY && process.env.WIKIVIBE_BASE_URL) {
    return { token: process.env.WIKIVIBE_API_KEY, baseUrl: process.env.WIKIVIBE_BASE_URL.replace(/\/+$/, '') };
  }
  const configPath = process.env.CODEX_HOME
    ? path.join(process.env.CODEX_HOME, 'config.toml')
    : path.join(homedir(), '.codex', 'config.toml');
  const found = providerFromConfig(await readFile(configPath, 'utf8'));
  if (!found) throw new Error('WikiVibe provider is not configured in ~/.codex/config.toml.');
  return found;
}

function decodeImage(body) {
  const output = Array.isArray(body?.output) ? body.output : [];
  for (const item of output) {
    if (item?.type !== 'image_generation_call') continue;
    if (item.status && item.status !== 'completed') continue;
    if (typeof item.result !== 'string' || !item.result) continue;
    const bytes = Buffer.from(item.result, 'base64');
    if (bytes.length < 8 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') continue;
    return { bytes, revisedPrompt: item.revised_prompt };
  }
  return null;
}

/// Builds a small JPEG preview with the macOS image tool, so the inline block
/// stays inside Codex's MCP result budget. Returns null when no preview can be
/// produced; the caller then falls back to the PNG or to text only.
async function preview(bytes) {
  const directory = await mkdtemp(path.join(tmpdir(), 'wikivibe-preview-'));
  try {
    const source = path.join(directory, 'full.png');
    const target = path.join(directory, 'preview.jpg');
    await writeFile(source, bytes, { mode: 0o600 });
    await run('/usr/bin/sips', [
      '-Z', String(PREVIEW_EDGE),
      '-s', 'format', 'jpeg',
      '-s', 'formatOptions', PREVIEW_FORMAT_OPTIONS,
      source, '--out', target
    ], { timeout: 30_000 });
    return { data: (await readFile(target)).toString('base64'), mimeType: 'image/jpeg' };
  } catch {
    return null;
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function safeName(prompt) {
  const slug = prompt.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return `wikivibe-${stamp}${slug ? `-${slug}` : ''}.png`;
}

async function generate(args) {
  const prompt = typeof args?.prompt === 'string' ? args.prompt.trim() : '';
  if (!prompt) throw new Error('prompt is required');
  if (prompt.length > 8000) throw new Error('prompt is too long');
  const model = typeof args?.model === 'string' && args.model.trim() ? args.model.trim() : DEFAULT_MODEL;
  if (!/^[A-Za-z0-9._-]{1,120}$/.test(model)) throw new Error('invalid model id');

  // Some upstream routes reject an image model unless the hosted tool is
  // declared; declaring it is accepted by every route we observed.
  const payload = { model, input: prompt, tools: [{ type: 'image_generation' }] };
  const size = typeof args?.size === 'string' ? args.size.trim() : '';
  if (/^\d{2,5}x\d{2,5}$/.test(size)) payload.size = size;
  const quality = typeof args?.quality === 'string' ? args.quality.trim() : '';
  if (['low', 'medium', 'high'].includes(quality)) payload.quality = quality;

  const { token, baseUrl } = await provider();
  const response = await fetch(`${baseUrl}/responses`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(payload),
    redirect: 'error',
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS)
  });

  const raw = await response.text();
  if (!response.ok) {
    let detail = '';
    try {
      const parsed = JSON.parse(raw);
      detail = parsed?.error?.message ?? parsed?.message ?? '';
    } catch {}
    throw new Error(`WikiVibe returned HTTP ${response.status}${detail ? `: ${String(detail).slice(0, 300)}` : ''}`);
  }

  let body;
  try { body = JSON.parse(raw); } catch { throw new Error('WikiVibe returned an unreadable response.'); }
  if (body?.code !== undefined && body.code !== 0) throw new Error(`WikiVibe error ${body.code}: ${String(body.message ?? '').slice(0, 300)}`);
  const image = decodeImage(body);
  if (!image) throw new Error('WikiVibe completed without an image in the response.');
  if (image.bytes.length > MAX_BYTES) throw new Error('Generated image exceeds the size limit.');

  const target = typeof args?.output_path === 'string' && path.isAbsolute(args.output_path)
    ? args.output_path
    : path.join(process.env.CODEX_HOME ?? path.join(homedir(), '.codex'), 'generated_images', safeName(prompt));
  await mkdir(path.dirname(target), { recursive: true, mode: 0o700 });
  await writeFile(target, image.bytes, { mode: 0o600 });

  const notes = [
    `Saved: ${target}`,
    `Display it now: call view_image with this exact path, or link it as ![generated image](${target})`,
    `Model: ${body.model ?? model}`,
    `Bytes: ${image.bytes.length}`
  ];
  if (image.revisedPrompt) notes.push(`Revised prompt: ${String(image.revisedPrompt).slice(0, 600)}`);
  const content = [{ type: 'text', text: notes.join('\n') }];
  const inline = (await preview(image.bytes))
    ?? { data: image.bytes.toString('base64'), mimeType: 'image/png' };
  if (inline.data.length <= INLINE_BUDGET) content.push({ type: 'image', ...inline });
  return { target, content };
}

// ---- JSON-RPC over stdio -------------------------------------------------

function send(message) {
  process.stdout.write(`${JSON.stringify(message)}\n`);
}

async function handle(request) {
  const { id, method, params } = request;
  if (method === 'initialize') {
    const requested = params?.protocolVersion;
    return {
      jsonrpc: '2.0', id,
      result: {
        protocolVersion: PROTOCOL_VERSIONS.includes(requested) ? requested : PROTOCOL_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: { name: 'wikivibe_images', title: 'WikiVibe images', version: '1.0.0' }
      }
    };
  }
  if (method === 'tools/list') {
    return { jsonrpc: '2.0', id, result: { tools: [tool] } };
  }
  if (method === 'tools/call') {
    if (params?.name !== tool.name) {
      return { jsonrpc: '2.0', id, result: { isError: true, content: [{ type: 'text', text: `Unknown tool: ${params?.name}` }] } };
    }
    try {
      const { content } = await generate(params?.arguments ?? {});
      return { jsonrpc: '2.0', id, result: { content } };
    } catch (error) {
      return { jsonrpc: '2.0', id, result: { isError: true, content: [{ type: 'text', text: `Image generation failed: ${error.message}` }] } };
    }
  }
  if (method === 'ping') return { jsonrpc: '2.0', id, result: {} };
  if (method === 'resources/list') return { jsonrpc: '2.0', id, result: { resources: [] } };
  if (method === 'prompts/list') return { jsonrpc: '2.0', id, result: { prompts: [] } };
  return { jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } };
}

let buffer = '';
let pending = 0;
let ended = false;
function finishIfDone() {
  if (!ended || pending > 0) return;
  // Flush the pipe before exiting: process.exit() truncates queued writes.
  process.stdout.write('', () => process.exit(0));
}
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffer += chunk;
  let index;
  while ((index = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, index).trim();
    buffer = buffer.slice(index + 1);
    if (!line) continue;
    let request;
    try { request = JSON.parse(line); } catch { continue; }
    if (request.id === undefined) continue; // notification
    pending++;
    handle(request).then(send).catch(error => send({
      jsonrpc: '2.0', id: request.id,
      error: { code: -32603, message: error.message }
    })).finally(() => { pending--; finishIfDone(); });
  }
});
process.stdin.on('end', () => { ended = true; finishIfDone(); });

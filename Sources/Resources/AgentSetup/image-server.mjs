import { constants, promises as fs } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ENDPOINTS = new Set(['https://api.wikivibe.dev/v1', 'https://vapi.wikivibe.dev/v1']);
const LIMIT = 64 * 1024 * 1024;
const imageID = id => id.startsWith('gpt-image-');
const carrierID = id => /^gpt-(?:[5-9]|[1-9]\d)(?:[.-]|$)/.test(id);
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);

export function imageTools(config, fetchImpl = fetch) {
  if (!object(config) || !ENDPOINTS.has(config.baseUrl) || typeof config.apiKey !== 'string' || !config.apiKey.trim() || /[\r\n]/.test(config.apiKey)
      || !Array.isArray(config.models) || config.models.some(id => typeof id !== 'string' || !id.trim())
      || (config.protocols != null && (!Array.isArray(config.protocols) || config.protocols.some(p => typeof p !== 'string')))) throw new Error('Invalid WikiVibe image-tool configuration.');
  const images = config.models.filter(imageID);
  const carriers = config.models.filter(carrierID);
  const responses = config.protocols == null || config.protocols.includes('openai_responses');
  const tools = [{
    name: 'list_models', description: 'List the complete configured WikiVibe model catalog, image IDs and Responses carrier IDs. No network request or inference.',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: { readOnlyHint: true, openWorldHint: false }
  }, ...(images.length ? [{
    name: 'generate_image',
    description: 'Generate an image through WikiVibe Responses image_generation. Use a text model for the conversation, not an image ID. This is a billable request when called; it is never run during setup. Requires Responses permission and an available GPT-5+ carrier. Returns an image and a private temporary file path. No retries or model substitution.',
    inputSchema: { type: 'object', properties: {
      model: { type: 'string', enum: images, description: 'Exact image model ID from list_models.' },
      prompt: { type: 'string', minLength: 1, maxLength: 32000 },
      carrier_model: { type: 'string', description: 'Optional exact GPT-5+ text carrier ID from list_models.' },
      size: { type: 'string', enum: ['auto', '1024x1024', '1536x1024', '1024x1536'], description: 'Requested output size. The gateway may return different dimensions; actual dimensions and a mismatch warning are returned without resizing or retrying.' }
    }, required: ['model', 'prompt'], additionalProperties: false },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: true }
  }] : [])];

  async function call(name, args = {}) {
    if (!object(args)) throw new Error('Tool arguments must be an object.');
    if (name === 'list_models') return { content: [{ type: 'text', text: JSON.stringify({ models: config.models, imageModels: images, carrierModels: carriers, responsesAllowed: responses }) }] };
    if (name !== 'generate_image') throw new Error('Unknown tool.');
    if (!images.includes(args.model) || typeof args.prompt !== 'string' || !args.prompt.trim() || args.prompt.length > 32000
        || Object.keys(args).some(key => !['model', 'prompt', 'carrier_model', 'size'].includes(key))
        || (args.size !== undefined && !['auto', '1024x1024', '1536x1024', '1024x1536'].includes(args.size))) throw new Error('Invalid image model, prompt, size or arguments.');
    if (!responses) throw new Error('This key does not allow OpenAI Responses. The model remains in the catalog; image generation requires a Responses-enabled key.');
    const carrier = args.carrier_model ?? carriers[0];
    if (!carriers.includes(carrier)) throw new Error('No selected GPT-5+ text carrier is available in this catalog. No request was sent.');
    let response;
    try {
      response = await fetchImpl(`${config.baseUrl}/responses`, {
        method: 'POST', redirect: 'error', signal: AbortSignal.timeout(180000),
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${config.apiKey}` },
        body: JSON.stringify({ model: carrier, input: args.prompt, store: false, stream: false,
          tools: [{ type: 'image_generation', model: args.model, output_format: 'png', ...(args.size ? { size: args.size } : {}) }],
          tool_choice: { type: 'image_generation' } })
      });
    } catch { throw new Error('WikiVibe image request failed or timed out. It was not retried; check usage before trying again.'); }
    if (!response.ok) {
      await response.body?.cancel();
      throw new Error(`WikiVibe image request returned HTTP ${response.status}. It was not retried; no upstream error body is exposed.`);
    }
    let body;
    try {
      const chunks = []; let length = 0;
      for await (const chunk of response.body) {
        length += chunk.length;
        if (length > LIMIT) throw new Error();
        chunks.push(chunk);
      }
      body = JSON.parse(Buffer.concat(chunks, length).toString('utf8'));
    } catch { throw new Error('WikiVibe returned an invalid or oversized image response. The request was not retried.'); }
    if (body.status !== 'completed' || !Array.isArray(body.output)) throw new Error('WikiVibe did not complete image generation. The request was not retried.');
    const generated = body.output.filter(item => item.type === 'image_generation_call');
    if (!generated.length || generated.length > 4) throw new Error('WikiVibe returned no image or too many images. No success is reported.');
    const decoded = generated.map(item => {
      if (item.status !== 'completed' || (item.model != null && item.model !== args.model) || typeof item.result !== 'string' || !item.result.length
          || item.result.length % 4 !== 0 || !/^[A-Za-z0-9+/]*={0,2}$/.test(item.result)) throw new Error('WikiVibe returned incomplete image data or a different image model.');
      const data = Buffer.from(item.result, 'base64');
      if (data.length < 24 || !data.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) || data.toString('ascii', 12, 16) !== 'IHDR') throw new Error('WikiVibe did not return the requested PNG image data.');
      const width = data.readUInt32BE(16), height = data.readUInt32BE(20);
      if (!width || !height) throw new Error('WikiVibe returned invalid PNG dimensions.');
      return { data, base64: item.result, width, height };
    });
    const directory = await fs.mkdtemp(path.join(os.tmpdir(), 'wikivibe-images-'));
    const paths = [];
    try {
      for (const image of decoded) {
        const target = path.join(directory, `${randomUUID()}.png`);
        await fs.writeFile(target, image.data, { flag: 'wx', mode: 0o600 });
        paths.push(target);
      }
    } catch { await fs.rm(directory, { recursive: true, force: true }); throw new Error('Image received, but saving the temporary file failed. The paid request was not retried.'); }
    const requestedSize = args.size ?? 'auto';
    const imageInfo = decoded.map((image, index) => ({ path: paths[index], width: image.width, height: image.height }));
    const sizeMismatch = requestedSize !== 'auto' && decoded.some(image => `${image.width}x${image.height}` !== requestedSize);
    return { content: [{ type: 'text', text: JSON.stringify({ requestedModel: args.model, carrierModel: carrier, imagePaths: paths, requestedSize, images: imageInfo, sizeMismatch,
      ...(sizeMismatch ? { warning: 'The gateway returned dimensions different from the requested size. The original image is preserved; no resize or retry was performed.' } : {}) }) },
      ...decoded.map(image => ({ type: 'image', mimeType: 'image/png', data: image.base64 }))] };
  }
  return { tools, call };
}

async function readConfig(filename) {
  const handle = await fs.open(filename, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o777) !== 0o600 || stat.size > 2 * 1024 * 1024 || (process.getuid && stat.uid !== process.getuid())) throw new Error();
    return JSON.parse(await handle.readFile('utf8'));
  } finally { await handle.close(); }
}

export function serve(config, input = process.stdin, output = process.stdout, fetchImpl = fetch) {
  const api = imageTools(config, fetchImpl);
  const write = value => output.write(`${JSON.stringify(value)}\n`);
  async function dispatch(message) {
    if (!object(message) || message.jsonrpc !== '2.0' || typeof message.method !== 'string') return write({ jsonrpc: '2.0', id: null, error: { code: -32600, message: 'Invalid request.' } });
    if (!Object.hasOwn(message, 'id')) return;
    const { id, method, params } = message;
    let result;
    if (method === 'initialize') result = { protocolVersion: ['2024-11-05', '2025-03-26', '2025-06-18'].includes(params?.protocolVersion) ? params.protocolVersion : '2025-06-18',
      capabilities: { tools: {} }, serverInfo: { name: 'wikivibe-images', version: '1.0.0' },
      instructions: 'Use list_models for the complete WikiVibe catalog. Keep a text model selected for coding. For images call generate_image with an exact image ID; selecting an image ID as the chat model does not generate images. Generation is billable only when explicitly called.' };
    else if (method === 'ping') result = {};
    else if (method === 'tools/list') result = { tools: api.tools };
    else if (method === 'tools/call') {
      try { result = await api.call(params?.name, params?.arguments); }
      catch (error) { result = { isError: true, content: [{ type: 'text', text: error.message }] }; }
    } else return write({ jsonrpc: '2.0', id, error: { code: -32601, message: 'Method not found.' } });
    write({ jsonrpc: '2.0', id, result });
  }
  let pending = '';
  input.setEncoding('utf8');
  input.on('data', chunk => {
    pending += chunk;
    for (;;) {
      const end = pending.indexOf('\n');
      if (end < 0) break;
      const line = pending.slice(0, end); pending = pending.slice(end + 1);
      if (line.length > 256 * 1024) { input.destroy(); return; }
      if (!line.trim()) continue;
      let message;
      try { message = JSON.parse(line); }
      catch { write({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Invalid JSON.' } }); continue; }
      void dispatch(message).catch(() => write({ jsonrpc: '2.0', id: message.id ?? null, error: { code: -32603, message: 'Internal image-tool error.' } }));
    }
    if (pending.length > 256 * 1024) input.destroy();
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { serve(await readConfig(process.argv[2])); }
  catch { process.stderr.write('WikiVibe image tools could not read their private configuration. Reapply setup.\n'); process.exitCode = 1; }
}

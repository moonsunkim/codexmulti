import http from 'node:http';
import https from 'node:https';
import { once } from 'node:events';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import {
  brotliDecompressSync,
  gunzipSync,
  inflateSync,
  zstdDecompressSync,
} from 'node:zlib';
import { calculateCooldownUntil } from './failover.mjs';

const ALWAYS_HOP_BY_HOP = new Set([
  'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization',
  'te', 'trailer', 'transfer-encoding', 'upgrade',
]);

function connectionTokens(headers) {
  const value = headers.connection;
  const joined = Array.isArray(value) ? value.join(',') : value ?? '';
  return new Set(String(joined).split(',').map((item) => item.trim().toLowerCase()).filter(Boolean));
}

export function stripHopByHop(headers) {
  const nominated = connectionTokens(headers);
  const output = {};
  for (const [key, value] of Object.entries(headers)) {
    const lower = key.toLowerCase();
    if (!ALWAYS_HOP_BY_HOP.has(lower) && !nominated.has(lower) && value !== undefined) {
      output[lower] = value;
    }
  }
  return output;
}

export function buildUpstreamHeaders(inbound, credentials, target, bodyLength) {
  const headers = stripHopByHop(inbound);
  for (const key of Object.keys(headers)) {
    const lower = key.toLowerCase();
    if (lower === 'authorization' || lower === 'chatgpt-account-id'
        || lower === 'host' || lower === 'content-length') delete headers[key];
  }
  headers.authorization = `Bearer ${credentials.accessToken}`;
  headers['chatgpt-account-id'] = credentials.accountId;
  headers.host = target.host;
  headers['content-length'] = String(bodyLength);
  return headers;
}

export function decodeForClassification(raw, encoding, maximumBytes = 1024 * 1024) {
  const normalized = String(encoding ?? 'identity').trim().toLowerCase();
  if (!normalized || normalized === 'identity') {
    if (raw.length > maximumBytes) throw new Error('classification_body_too_large');
    return raw;
  }
  const options = { maxOutputLength: maximumBytes };
  if (normalized === 'gzip' || normalized === 'x-gzip') return gunzipSync(raw, options);
  if (normalized === 'deflate') return inflateSync(raw, options);
  if (normalized === 'br') return brotliDecompressSync(raw, options);
  if (normalized === 'zstd') return zstdDecompressSync(raw, options);
  throw new Error('unsupported_content_encoding');
}

export function classify429(raw, headers, options = {}) {
  let body;
  try {
    const decoded = decodeForClassification(raw, headers['content-encoding']);
    body = JSON.parse(decoded.toString('utf8'));
  } catch {
    return { usageLimit: false, body: null, cooldownUntil: null };
  }
  if (body?.error?.type !== 'usage_limit_reached') {
    return { usageLimit: false, body, cooldownUntil: null };
  }
  return {
    usageLimit: true,
    body,
    cooldownUntil: calculateCooldownUntil({
      body,
      headers,
      now: options.now ?? Date.now(),
      defaultSeconds: options.defaultSeconds ?? 1800,
      marginSeconds: options.marginSeconds ?? 60,
    }),
  };
}

export function createUpstreamAgents() {
  return {
    http: new http.Agent({ keepAlive: true }),
    https: new https.Agent({ keepAlive: true }),
  };
}

export async function openUpstream({ method, target, headers, body, agents, connectTimeoutMs = 10_000 }) {
  const url = target instanceof URL ? target : new URL(target);
  const transport = url.protocol === 'https:' ? https : url.protocol === 'http:' ? http : null;
  if (!transport) throw new Error('unsupported_upstream_protocol');
  return await new Promise((resolve, reject) => {
    let settled = false;
    let timer = null;
    const request = transport.request(url, {
      method,
      headers,
      agent: url.protocol === 'https:' ? agents.https : agents.http,
    }, (response) => {
      settled = true;
      if (timer) clearTimeout(timer);
      resolve({ request, response });
    });
    request.once('socket', (socket) => {
      if (!socket.connecting) return;
      timer = setTimeout(() => request.destroy(new Error('upstream_connect_timeout')), connectTimeoutMs);
      const event = url.protocol === 'https:' ? 'secureConnect' : 'connect';
      socket.once(event, () => {
        if (timer) clearTimeout(timer);
        timer = null;
      });
    });
    request.once('error', (error) => {
      if (timer) clearTimeout(timer);
      if (!settled) reject(error);
    });
    request.end(body);
  });
}

export async function bufferForClassification(response, limit = 1024 * 1024) {
  return await new Promise((resolve, reject) => {
    const chunks = [];
    let length = 0;
    const cleanup = () => {
      response.off('data', onData);
      response.off('end', onEnd);
      response.off('error', onError);
      response.off('aborted', onAborted);
    };
    const onData = (chunk) => {
      chunks.push(chunk);
      length += chunk.length;
      if (length > limit) {
        response.pause();
        cleanup();
        resolve({ complete: false, prefix: Buffer.concat(chunks, length) });
      }
    };
    const onEnd = () => {
      cleanup();
      resolve({ complete: true, raw: Buffer.concat(chunks, length) });
    };
    const onError = (error) => {
      cleanup();
      reject(error);
    };
    const onAborted = () => {
      cleanup();
      reject(new Error('upstream_response_aborted'));
    };
    response.on('data', onData);
    response.once('end', onEnd);
    response.once('error', onError);
    response.once('aborted', onAborted);
  });
}

export async function discardResponse(response) {
  response.resume();
  if (!response.complete) {
    await Promise.race([
      once(response, 'end'),
      once(response, 'error').catch(() => []),
      once(response, 'close'),
    ]).catch(() => {});
  }
}

export function responseHeaders(response) {
  return stripHopByHop(response.headers);
}

export async function sendBuffered(downstream, statusCode, headers, raw) {
  if (downstream.destroyed) return;
  downstream.writeHead(statusCode, responseHeaders({ headers }));
  downstream.end(raw);
}

export async function streamResponse(downstream, upstreamResponse, prefix = null, upstreamRequest = null) {
  const termination = {
    first: null,
    relayedBytes: 0,
    terminalSeen: false,
    upstreamErrorCode: null,
  };
  const terminalMarkers = [
    Buffer.from('response.completed'),
    Buffer.from('response.failed'),
    Buffer.from('response.incomplete'),
  ];
  let terminalCarry = Buffer.alloc(0);
  const observe = (chunk) => {
    termination.relayedBytes += chunk.length;
    if (termination.terminalSeen) return;
    const searchable = terminalCarry.length ? Buffer.concat([terminalCarry, chunk]) : chunk;
    termination.terminalSeen = terminalMarkers.some((marker) => searchable.includes(marker));
    terminalCarry = Buffer.from(searchable.subarray(Math.max(0, searchable.length - 256)));
  };
  const result = (outcome, errorCode = null) => ({
    outcome,
    relayedBytes: termination.relayedBytes,
    terminalSeen: termination.terminalSeen,
    errorCode,
  });
  if (downstream.destroyed) {
    upstreamRequest?.destroy();
    upstreamResponse.destroy();
    return result('client_closed');
  }
  downstream.writeHead(upstreamResponse.statusCode ?? 502, responseHeaders(upstreamResponse));
  let settled = false;
  const downstreamSocket = downstream.socket;
  const upstreamSocket = upstreamResponse.socket;
  const onDownstreamClose = () => {
    if (!settled && !downstream.writableEnded) {
      if (!termination.first) termination.first = 'downstream';
      upstreamRequest?.destroy();
      upstreamResponse.destroy();
    }
  };
  const onUpstreamGone = (error) => {
    if (!termination.first) termination.first = 'upstream';
    if (error?.code) termination.upstreamErrorCode = String(error.code);
  };
  const onUpstreamSocketClose = () => {
    if (!settled && !upstreamResponse.complete && !termination.first) {
      termination.first = 'upstream';
    }
  };
  const inspector = new Transform({
    transform(chunk, _encoding, callback) {
      observe(chunk);
      callback(null, chunk);
    },
  });
  downstreamSocket?.once('close', onDownstreamClose);
  upstreamResponse.once('aborted', onUpstreamGone);
  upstreamResponse.once('error', onUpstreamGone);
  upstreamSocket?.once('close', onUpstreamSocketClose);
  try {
    if (prefix?.length) {
      observe(prefix);
      downstream.write(prefix);
    }
    await pipeline(upstreamResponse, inspector, downstream);
    settled = true;
    return result('complete');
  } catch (error) {
    settled = true;
    if (termination.first === 'downstream') return result('client_closed');
    downstream.destroy();
    return result('upstream_stream_error',
      termination.upstreamErrorCode ?? String(error?.code ?? 'UPSTREAM_STREAM_ERROR'));
  } finally {
    settled = true;
    downstreamSocket?.off('close', onDownstreamClose);
    upstreamResponse.off('aborted', onUpstreamGone);
    upstreamResponse.off('error', onUpstreamGone);
    upstreamSocket?.off('close', onUpstreamSocketClose);
  }
}

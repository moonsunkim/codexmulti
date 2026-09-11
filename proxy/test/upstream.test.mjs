import test from 'node:test';
import assert from 'node:assert/strict';
import { gzipSync, zstdCompressSync } from 'node:zlib';
import {
  buildUpstreamHeaders,
  buildUpstreamUpgradeHeaders,
  classify429,
  decodeForClassification,
  stripHopByHop,
} from '../src/upstream.mjs';

test('only identity headers and Host are replaced while end-to-end Codex headers survive', () => {
  const target = new URL('https://chatgpt.com/backend-api/codex/responses');
  const headers = buildUpstreamHeaders({
    authorization: 'Bearer inbound-secret',
    'chatgpt-account-id': 'inbound-account',
    host: '127.0.0.1:8787',
    connection: 'keep-alive, x-remove-me',
    'x-remove-me': 'hop-value',
    'user-agent': 'codex_exec/0.153.2',
    originator: 'codex_exec',
    'session-id': 'synthetic-session',
    'openai-beta': 'responses_websockets=2026-02-06',
    'x-codex-routing-hint': 'synthetic-hint',
    'x-openai-internal-codex-responses-lite': 'true',
    'content-encoding': 'zstd',
  }, { accessToken: 'selected-token', accountId: 'selected-account' }, target, 19);
  assert.equal(headers.authorization, 'Bearer selected-token');
  assert.equal(headers['chatgpt-account-id'], 'selected-account');
  assert.equal(headers.host, 'chatgpt.com');
  assert.equal(headers['content-length'], '19');
  assert.equal(headers['session-id'], 'synthetic-session');
  assert.equal(headers['openai-beta'], 'responses_websockets=2026-02-06');
  assert.equal(headers['x-codex-routing-hint'], 'synthetic-hint');
  assert.equal(headers['x-openai-internal-codex-responses-lite'], 'true');
  assert.equal(headers['content-encoding'], 'zstd');
  assert.equal(headers.connection, undefined);
  assert.equal(headers['x-remove-me'], undefined);
});

test('response hop-by-hop headers are stripped without dropping end-to-end headers', () => {
  assert.deepEqual(stripHopByHop({
    connection: 'close, x-hop',
    'x-hop': 'remove',
    'transfer-encoding': 'chunked',
    'x-request-id': 'synthetic-request',
    'content-type': 'text/event-stream',
  }), {
    'x-request-id': 'synthetic-request',
    'content-type': 'text/event-stream',
  });
});

test('WebSocket handshake replaces identity headers and preserves upgrade metadata', () => {
  const target = new URL('https://chatgpt.com/backend-api/codex/responses?fixture=1');
  const headers = buildUpstreamUpgradeHeaders({
    authorization: 'Bearer inbound-secret',
    'chatgpt-account-id': 'inbound-account',
    host: '127.0.0.1:8787',
    connection: 'keep-alive, Upgrade, x-remove-me',
    upgrade: 'websocket',
    'x-remove-me': 'hop-value',
    'sec-websocket-key': 'synthetic-key',
    'sec-websocket-version': '13',
    'openai-beta': 'responses_websockets=2026-02-06',
    'content-length': '99',
  }, { accessToken: 'selected-token', accountId: 'selected-account' }, target);
  assert.equal(headers.authorization, 'Bearer selected-token');
  assert.equal(headers['chatgpt-account-id'], 'selected-account');
  assert.equal(headers.host, 'chatgpt.com');
  assert.equal(headers.connection, 'Upgrade');
  assert.equal(headers.upgrade, 'websocket');
  assert.equal(headers['sec-websocket-key'], 'synthetic-key');
  assert.equal(headers['sec-websocket-version'], '13');
  assert.equal(headers['openai-beta'], 'responses_websockets=2026-02-06');
  assert.equal(headers['content-length'], undefined);
  assert.equal(headers['x-remove-me'], undefined);
});

for (const [encoding, compress] of [['gzip', gzipSync], ['zstd', zstdCompressSync]]) {
  test(`${encoding} compressed usage limit is classified from a decoded copy`, () => {
    const json = Buffer.from(JSON.stringify({ error: { type: 'usage_limit_reached', resets_at: 2_000_000_000 } }));
    const raw = compress(json);
    const result = classify429(raw, { 'content-encoding': encoding }, { now: 1_900_000_000_000, marginSeconds: 60 });
    assert.equal(result.usageLimit, true);
    assert.equal(result.cooldownUntil, 2_000_000_060_000);
    assert.deepEqual(raw, compress(json));
    assert.deepEqual(decodeForClassification(raw, encoding), json);
  });
}

test('usage_not_included and other 429 bodies remain terminal and unclassified', () => {
  const raw = Buffer.from(JSON.stringify({ error: { type: 'usage_not_included' } }));
  assert.deepEqual(classify429(raw, {}), { usageLimit: false, body: { error: { type: 'usage_not_included' } }, cooldownUntil: null });
  assert.equal(classify429(Buffer.from('not-json'), {}).usageLimit, false);
  assert.equal(classify429(raw, { 'content-encoding': 'unsupported' }).usageLimit, false);
});

test('compressed classification refuses decompressed bodies over 1 MiB', () => {
  const compressed = gzipSync(Buffer.alloc(1024 * 1024 + 1, 0x61));
  assert.throws(() => decodeForClassification(compressed, 'gzip'), /Cannot create a Buffer larger|larger than/);
  assert.equal(classify429(compressed, { 'content-encoding': 'gzip' }).usageLimit, false);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { main } from '../src/cli.mjs';
import { jwt, request, startHttpServer, startTestProxy } from './helpers.mjs';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

async function filesBelow(directory) {
  const output = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (entry.name === '.git' || entry.name.startsWith('.tmp-')) continue;
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...await filesBelow(full));
    else output.push(full);
  }
  return output;
}

test('tracked-source secret scan finds no API keys or unlabelled token values', async () => {
  const findings = [];
  for (const file of await filesBelow(root)) {
    const text = await readFile(file, 'utf8').catch(() => null);
    if (text === null) continue;
    for (const match of text.matchAll(/\bsk-[A-Za-z0-9_-]{20,}\b/g)) {
      findings.push(`${path.relative(root, file)}:api-key:${match[0].slice(0, 5)}`);
    }
    for (const match of text.matchAll(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{6,}\b/g)) {
      if (!match[0].includes('synthetic')) findings.push(`${path.relative(root, file)}:jwt`);
    }
    for (const match of text.matchAll(/"(?:access_token|refresh_token|id_token|account_id)"\s*:\s*"([^"]+)"/g)) {
      const value = match[1];
      if (!value.includes('synthetic') && !/^<(?:secret|redacted)>$/.test(value)) {
        findings.push(`${path.relative(root, file)}:token-field`);
      }
    }
  }
  assert.deepEqual(findings, []);
});

test('import and refresh CLI outputs contain no credential material', async (t) => {
  let importOutput = '';
  const importExit = await main([
    'import-codexmulti', '--store', '/synthetic/store', '--out', '/synthetic/out', '--dry-run',
  ], {
    importCodexMulti: async () => ({
      ok: true,
      rows: [{
        name: 'codex-1', label: 'label-1',
        accessExpiresAt: '2030-01-02T00:00:00.000Z', validation: 'ok',
      }],
      warnings: [],
    }),
    stdout: { write: (chunk) => { importOutput += chunk; } },
    stderr: { write: () => {} },
  });
  assert.equal(importExit, 0);

  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    now,
    options: {
      refreshRequest: async () => ({
        access_token: jwt({ exp: Math.floor(now / 1000) + 10 * 86_400, token_name: 'safe-output' }),
        refresh_token: 'synthetic-refresh-safe-output',
      }),
    },
  });
  let refreshOutput = '';
  const refreshExit = await main(['--config', '/synthetic/config.json', 'refresh', 'a'], {
    loadConfig: async () => ({
      ...started.proxy.config,
      port: started.proxy.server.address().port,
    }),
    stdout: { write: (chunk) => { refreshOutput += chunk; } },
  });
  assert.equal(refreshExit, 0);
  const combined = `${importOutput}\n${refreshOutput}`;
  assert.doesNotMatch(combined, /Bearer|\beyJ|synthetic-refresh|synthetic-account|account_id|access_token|id_token/i);
  assert.deepEqual(JSON.parse(refreshOutput), {
    name: 'a',
    result: 'ok',
    access_expires_at: '2030-01-11T00:00:00.000Z',
  });
});

test('status v2 and reload-config responses contain no credential material', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    labelsByName: { a: 'Safe label' },
  });
  const status = await request(started.origin, '/_proxy/status');
  const reloaded = await request(started.origin, '/_proxy/reload-config', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: '{}',
  });
  assert.equal(JSON.parse(status.body).version, 2);
  assert.equal(reloaded.statusCode, 200);
  const combined = `${status.body.toString()}\n${reloaded.body.toString()}`;
  assert.doesNotMatch(combined,
    /access_token|refresh_token|id_token|account_id|authorization|synthetic-refresh|synthetic-account/i);
});

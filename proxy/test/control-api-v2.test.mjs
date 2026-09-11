import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { chmod, readFile, writeFile } from 'node:fs/promises';
import {
  makeTempDir,
  request,
  sseOk,
  startHttpServer,
  startTestProxy,
  syntheticAuth,
  writeAccountAuth,
} from './helpers.mjs';

async function post(origin, route, body = '{}') {
  return await request(origin, route, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body,
  });
}

async function replaceConfig(started, change) {
  const current = JSON.parse(await readFile(started.configPath, 'utf8'));
  const next = change(structuredClone(current));
  await writeFile(started.configPath, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 });
  return next;
}

test('status v2 exposes labels, normalized auth paths, and fixed config path without credentials', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b'],
    labelsByName: { a: 'Primary' },
  });
  const response = await request(started.origin, '/_proxy/status');
  assert.equal(response.statusCode, 200);
  const status = JSON.parse(response.body);
  assert.equal(status.version, 2);
  assert.equal(status.config_path, path.resolve(started.configPath));
  assert.deepEqual(status.accounts.map(({ name, label, auth_file }) => ({ name, label, auth_file })), [
    { name: 'a', label: 'Primary', auth_file: path.resolve(started.accounts[0].auth_file) },
    { name: 'b', label: null, auth_file: path.resolve(started.accounts[1].auth_file) },
  ]);
  assert.doesNotMatch(response.body.toString(),
    /access_token|refresh_token|id_token|account_id|authorization|synthetic-refresh|synthetic-account/i);
});

test('reload-config adds a new auth file as READY and logs only safe migration counts', async (t) => {
  const events = [];
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { logger: (event) => events.push(event) },
  });
  events.length = 0;
  const authFile = await writeAccountAuth(
    started.root, 'new-identity', syntheticAuth('new-identity', 4_102_444_800),
  );
  await replaceConfig(started, (config) => ({
    ...config,
    accounts: [...config.accounts, { name: 'b', label: 'New account', auth_file: authFile }],
  }));
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 200);
  const status = JSON.parse(response.body);
  assert.deepEqual(status.accounts.map(({ name, state }) => ({ name, state })), [
    { name: 'a', state: 'READY' },
    { name: 'b', state: 'READY' },
  ]);
  assert.deepEqual(events, [{
    timestamp: events[0].timestamp,
    level: 'info',
    event: 'config_reloaded',
    added: 1,
    removed: 0,
    renamed: 0,
    migrated: 1,
  }]);
  assert.doesNotMatch(JSON.stringify(events), /auth\.json|New account|synthetic-refresh|synthetic-account/i);
});

test('reload-config removes absent auth files and resets cursor when its owner is removed', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  await started.proxy.failover.switchTo('a');
  await started.proxy.failover.pause('a');
  await replaceConfig(started, (config) => ({ ...config, accounts: [config.accounts[1]] }));
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 200);
  const status = JSON.parse(response.body);
  assert.deepEqual(status.accounts.map(({ name }) => name), ['b']);
  assert.equal(status.cursor, 'b');
  const state = JSON.parse(await readFile(started.proxy.config.state_file, 'utf8'));
  assert.deepEqual(Object.keys(state.accounts), ['b']);
});

test('reload-config reorder keeps cooldown and cursor with the exact auth file owner', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin, accountNames: ['a', 'b'], now,
  });
  await started.proxy.failover.markCooldown('a', now + 60_000);
  await started.proxy.failover.switchTo('a');
  await replaceConfig(started, (config) => ({
    ...config,
    accounts: [
      { ...config.accounts[1], name: 'a' },
      { ...config.accounts[0], name: 'b' },
    ],
  }));
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 200);
  const status = JSON.parse(response.body);
  assert.equal(status.cursor, 'b');
  assert.equal(status.accounts.find(({ name }) => name === 'b').state, 'COOLDOWN');
  assert.equal(status.accounts.find(({ name }) => name === 'a').state, 'READY');
});

test('reload-config migrates pause, cooldown, INVALID, and cursor by auth_file across renames', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin, accountNames: ['a', 'b', 'c'], now,
  });
  await started.proxy.failover.markCooldown('a', now + 60_000);
  await started.proxy.failover.pause('b');
  await started.proxy.failover.markInvalid('c');
  await started.proxy.failover.switchTo('c');
  await replaceConfig(started, (config) => ({
    ...config,
    accounts: [
      { ...config.accounts[2], name: 'x' },
      { ...config.accounts[0], name: 'y' },
      { ...config.accounts[1], name: 'z' },
    ],
  }));
  const status = JSON.parse((await post(started.origin, '/_proxy/reload-config')).body);
  assert.equal(status.cursor, 'x');
  assert.equal(status.accounts.find(({ name }) => name === 'x').state, 'INVALID');
  assert.equal(status.accounts.find(({ name }) => name === 'y').state, 'COOLDOWN');
  assert.equal(status.accounts.find(({ name }) => name === 'z').state, 'PAUSED');
});

test('reload-config returns proxy_busy without changing the live generation', async (t) => {
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  t.after(() => release());
  let began;
  const startedRequest = new Promise((resolve) => { began = resolve; });
  const upstream = await startHttpServer(t, async (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('event: response.created\ndata: {"type":"response.created"}\n\n');
    began();
    await held;
    res.end(sseOk());
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const stream = request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  await startedRequest;
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: 'proxy_busy', in_flight: 1 });
  assert.deepEqual((await started.proxy.statusPayload()).accounts.map(({ name }) => name), ['a']);
  release();
  await stream;
});

test('reload-config rejects immutable changes and preserves the old generation', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  await replaceConfig(started, (config) => ({ ...config, default_cooldown_seconds: 999 }));
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: 'restart_required' });
  assert.equal(started.proxy.config.default_cooldown_seconds, 1800);
});

test('reload-config validation failures roll back config and credential candidates', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  await writeFile(started.configPath, '{broken', { mode: 0o600 });
  const invalidConfig = await post(started.origin, '/_proxy/reload-config');
  assert.equal(invalidConfig.statusCode, 409);
  assert.deepEqual(JSON.parse(invalidConfig.body), { error: 'invalid_config_file' });
  assert.deepEqual((await started.proxy.statusPayload()).accounts.map(({ name }) => name), ['a']);

  const badAuth = path.join(started.root, 'bad', 'auth.json');
  await writeAccountAuth(started.root, 'bad', { auth_mode: 'chatgpt', tokens: {} });
  const current = started.proxy.config;
  await writeFile(started.configPath, `${JSON.stringify({
    ...current,
    accounts: [...current.accounts, { name: 'bad', auth_file: badAuth }],
  }, null, 2)}\n`, { mode: 0o600 });
  await chmod(path.dirname(badAuth), 0o700);
  const invalidAuth = await post(started.origin, '/_proxy/reload-config');
  assert.equal(invalidAuth.statusCode, 409);
  assert.deepEqual(JSON.parse(invalidAuth.body), { error: 'invalid_credentials' });
  assert.deepEqual((await started.proxy.statusPayload()).accounts.map(({ name }) => name), ['a']);
});

test('reload-config gate rejects new upstream admission with 503 and then commits', async (t) => {
  let enterGate;
  const enteredGate = new Promise((resolve) => { enterGate = resolve; });
  let releaseGate;
  const holdGate = new Promise((resolve) => { releaseGate = resolve; });
  t.after(() => releaseGate());
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: {
      beforeReloadCommit: async () => {
        enterGate();
        await holdGate;
      },
    },
  });
  const reload = post(started.origin, '/_proxy/reload-config');
  await Promise.race([
    enteredGate,
    new Promise((_, reject) => setTimeout(() => reject(new Error('reload_gate_not_entered')), 250)),
  ]);
  const rejected = await request(started.origin, '/backend-api/codex/responses', {
    method: 'POST', body: '{}',
  });
  assert.equal(rejected.statusCode, 503);
  assert.deepEqual(JSON.parse(rejected.body), { error: 'proxy_reconfiguring' });
  releaseGate();
  assert.equal((await reload).statusCode, 200);
});

test('reload-config requires an exact empty JSON object body', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  for (const body of ['', '[]', 'null', '{"config_path":"/synthetic/other.json"}']) {
    const response = await post(started.origin, '/_proxy/reload-config', body);
    assert.equal(response.statusCode, 400);
    assert.deepEqual(JSON.parse(response.body), { error: 'body_must_be_empty_object' });
  }
});

test('reload-config reports unavailable when no startup config path was fixed', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: { configPath: null },
  });
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 409);
  assert.deepEqual(JSON.parse(response.body), { error: 'config_reload_unavailable' });
});

test('reload-config state write failure keeps the previous live generation', async (t) => {
  let failWrites = false;
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const { atomicWriteJson } = await import('../src/accounts.mjs');
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    options: {
      stateWriter: async (...args) => {
        if (failWrites) throw new Error('synthetic_state_write_failure');
        return await atomicWriteJson(...args);
      },
    },
  });
  const authFile = await writeAccountAuth(
    started.root, 'candidate', syntheticAuth('candidate', 4_102_444_800),
  );
  await replaceConfig(started, (config) => ({
    ...config, accounts: [...config.accounts, { name: 'b', auth_file: authFile }],
  }));
  failWrites = true;
  const response = await post(started.origin, '/_proxy/reload-config');
  assert.equal(response.statusCode, 500);
  assert.deepEqual(JSON.parse(response.body), { error: 'config_reload_failed' });
  assert.deepEqual((await started.proxy.statusPayload()).accounts.map(({ name }) => name), ['a']);
});

test('clear-cooldown clears only the cooldown and returns the account row', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin, accountNames: ['a', 'b'], now,
  });
  await started.proxy.failover.markCooldown('a', now + 5 * 86_400_000);
  await started.proxy.failover.markCooldown('b', now + 6 * 86_400_000);
  const response = await post(started.origin, '/_proxy/accounts/a/clear-cooldown');
  assert.equal(response.statusCode, 200);
  assert.deepEqual(JSON.parse(response.body), { name: 'a', state: 'READY', cooldown_until: null });
  assert.doesNotMatch(response.body.toString(),
    /access_token|refresh_token|id_token|account_id|authorization|auth\.json|synthetic-refresh|synthetic-account/i);
  const status = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(status.active, 'a');
  assert.deepEqual(status.accounts.map(({ name, state, reason }) => ({ name, state, reason })), [
    { name: 'a', state: 'READY', reason: null },
    { name: 'b', state: 'COOLDOWN', reason: 'usage_limit_reached' },
  ]);
  const persisted = JSON.parse(await readFile(started.proxy.config.state_file, 'utf8'));
  assert.equal(persisted.accounts.a.cooldown_until, null);
  assert.equal(persisted.accounts.a.reason, null);
  assert.equal(persisted.accounts.b.cooldown_until, new Date(now + 6 * 86_400_000).toISOString());
});

test('clear-cooldown returns 404 for an unknown account name', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const response = await post(started.origin, '/_proxy/accounts/absent/clear-cooldown');
  assert.equal(response.statusCode, 404);
  assert.deepEqual(JSON.parse(response.body), { error: 'unknown_account' });
});

test('clear-cooldown refuses PAUSED and INVALID accounts and leaves their state intact', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin, accountNames: ['a', 'b'], now,
  });
  await started.proxy.failover.markCooldown('a', now + 60_000);
  await started.proxy.failover.pause('a');
  await started.proxy.failover.markCooldown('b', now + 60_000);
  await started.proxy.failover.markInvalid('b');
  const paused = await post(started.origin, '/_proxy/accounts/a/clear-cooldown');
  assert.equal(paused.statusCode, 409);
  assert.deepEqual(JSON.parse(paused.body), { error: 'account_paused' });
  const invalid = await post(started.origin, '/_proxy/accounts/b/clear-cooldown');
  assert.equal(invalid.statusCode, 409);
  assert.deepEqual(JSON.parse(invalid.body), { error: 'account_invalid' });
  const status = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.deepEqual(status.accounts.map(({ name, state, cooldown_until: until }) => ({ name, state, until })), [
    { name: 'a', state: 'PAUSED', until: new Date(now + 60_000).toISOString() },
    { name: 'b', state: 'INVALID', until: new Date(now + 60_000).toISOString() },
  ]);
});

test('clear-cooldown requires an exact empty JSON object body', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  for (const body of ['', '[]', 'null', '{"name":"a"}']) {
    const response = await post(started.origin, '/_proxy/accounts/a/clear-cooldown', body);
    assert.equal(response.statusCode, 400);
    assert.deepEqual(JSON.parse(response.body), { error: 'body_must_be_empty_object' });
  }
  const untyped = await request(started.origin, '/_proxy/accounts/a/clear-cooldown', {
    method: 'POST', body: '{}',
  });
  assert.equal(untyped.statusCode, 415);
  assert.deepEqual(JSON.parse(untyped.body), { error: 'content_type_required' });
  const wrongMethod = await request(started.origin, '/_proxy/accounts/a/clear-cooldown');
  assert.equal(wrongMethod.statusCode, 404);
  assert.deepEqual(JSON.parse(wrongMethod.body), { error: 'control_not_found' });
});

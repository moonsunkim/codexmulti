import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { createLogger, validateConfig, redactSecret } from '../src/server.mjs';
import { main, parseArgs, runLogin } from '../src/cli.mjs';
import { jwt, makeTempDir, request, startHttpServer, startTestProxy } from './helpers.mjs';
import path from 'node:path';
import { readFile, stat } from 'node:fs/promises';

const base = {
  listen_host: '127.0.0.1',
  port: 8787,
  mode: 'failover',
  accounts: [{ name: 'a', auth_file: '/synthetic/a/auth.json' }],
  upstream_chatgpt_base_url: 'https://chatgpt.com/backend-api/',
  upstream_openai_base_url: 'https://chatgpt.com/backend-api/codex',
  allow_insecure_upstream: false,
};

test('config enforces loopback, production origins, and round_robin startup refusal', () => {
  const validated = validateConfig({
    ...base,
    accounts: [{ ...base.accounts[0], label: 'Primary account' }],
  });
  assert.equal(validated.listen_host, '127.0.0.1');
  assert.equal(validated.token_refresh_skew_seconds, 172_800);
  assert.equal(validated.accounts[0].label, 'Primary account');
  assert.throws(() => validateConfig({ ...base, listen_host: '0.0.0.0' }), /loopback/);
  assert.throws(() => validateConfig({ ...base, upstream_openai_base_url: 'https://example.com/v1' }), /invalid_upstream/);
  assert.throws(() => validateConfig({ ...base, mode: 'round_robin' }), /not_implemented/);
  assert.throws(() => validateConfig({ ...base, accounts: [{ name: '../escape', auth_file: '/x' }] }), /invalid_account/);
  assert.throws(() => validateConfig({
    ...base, accounts: [{ ...base.accounts[0], label: 123 }],
  }), /invalid_account/);
  assert.throws(() => validateConfig({
    ...base,
    accounts: [{ name: 'a', auth_file: '/synthetic/a/../escape/auth.json' }],
  }), /auth_path_escape/);
  assert.throws(() => validateConfig({
    ...base,
    accounts: [{ name: 'a', auth_file: '/synthetic/a/credentials.json' }],
  }), /invalid_auth_file_name/);
  assert.throws(() => validateConfig({
    ...base,
    accounts: [{ name: 'a', auth_file: '~/.codex/auth.json' }],
  }, { home: '/synthetic/home' }), /main_auth_file_forbidden/);
  assert.throws(() => validateConfig({
    ...base,
    accounts: [
      { name: 'a', auth_file: '/synthetic/shared/auth.json' },
      { name: 'b', auth_file: '/synthetic/shared/auth.json' },
    ],
  }), /duplicate_auth_file/);
  assert.throws(() => validateConfig({
    ...base,
    state_file: '/synthetic/a/auth.json',
  }), /runtime_file_conflicts_with_auth/);
});

test('allow_insecure_upstream permits only http://127.0.0.1 test origins', () => {
  const config = validateConfig({
    ...base,
    allow_insecure_upstream: true,
    upstream_chatgpt_base_url: 'http://127.0.0.1:1234/backend-api/',
    upstream_openai_base_url: 'http://127.0.0.1:1234/backend-api/codex',
  });
  assert.match(config.upstream_openai_base_url, /^http:\/\/127\.0\.0\.1/);
  assert.throws(() => validateConfig({
    ...base,
    allow_insecure_upstream: true,
    upstream_chatgpt_base_url: 'http://localhost:1234/backend-api/',
    upstream_openai_base_url: 'http://localhost:1234/backend-api/codex',
  }), /invalid_insecure_upstream/);
});

test('absolute-form and userinfo-like targets are rejected by ingress routing', async () => {


  assert.throws(() => validateConfig({
    ...base,
    upstream_openai_base_url: 'https://user@example.com/backend-api/codex',
  }), /invalid_upstream/);
});

test('redaction removes secret keys and Bearer/JWT/refresh-token string forms', () => {
  const jwtValue = 'eyJhbGciOiJub25lIn0.eyJleHAiOjQxMDI0NDQ4MDB9.synthetic';
  const redacted = redactSecret({
    authorization: `Bearer ${jwtValue}`,
    cookie: 'session=synthetic',
    nested: { access_token: jwtValue, message: `failed Bearer ${jwtValue} refresh-synthetic-value` },
    allowed: 'account-name-is-not-a-secret-here',
  });
  assert.equal(redacted.authorization, '<redacted>');
  assert.equal(redacted.cookie, '<redacted>');
  assert.equal(redacted.nested.access_token, '<redacted>');
  assert.doesNotMatch(JSON.stringify(redacted), /eyJ|refresh-synthetic-value|session=synthetic/);
});

test('logger keeps only allowlisted fields, retains safe account names, rotates, and writes mode 0600', async (t) => {
  const root = await makeTempDir(t);
  const logFile = path.join(root, 'proxy.log');
  const logger = createLogger(logFile, { maximumBytes: 1, backups: 2 });
  logger({
    timestamp: new Date(0).toISOString(), level: 'info', event: 'fixture',
    account_name: 'a', upstream_status: 200, relayed_bytes: 123,
    terminal_seen: true, error_code: 'SYNTHETIC_STREAM_CODE',
    error_message: 'bounded synthetic diagnostic',
    authorization: 'Bearer secret', body: 'must-not-log', tail: 'must-not-log-tail',
  });
  logger({ timestamp: new Date(1).toISOString(), level: 'info', event: 'fixture-2', account_name: 'b' });
  assert.equal((await stat(logFile)).mode & 0o777, 0o600);
  const combined = `${await readFile(logFile, 'utf8')}\n${await readFile(`${logFile}.1`, 'utf8')}`;
  assert.match(combined, /"account_name":"a"/);
  assert.match(combined, /"account_name":"b"/);
  assert.match(combined, /"upstream_status":200/);
  assert.match(combined, /"terminal_seen":true/);
  assert.doesNotMatch(combined, /authorization|must-not-log|Bearer secret|tail/);
});

test('CLI parses config independently of command position', async () => {
  const switched = parseArgs(['--config', '/tmp/synthetic.json', 'switch', 'b']);
  assert.equal(switched.configPath, '/tmp/synthetic.json');
  assert.equal(switched.command, 'switch');
  assert.equal(switched.name, 'b');
  assert.deepEqual(switched.extra, []);
  const labelled = parseArgs(['status', '--labels', '--config', '/tmp/synthetic.json']);
  assert.equal(labelled.command, 'status');
  assert.equal(labelled.labels, true);
  assert.equal(labelled.configPath, '/tmp/synthetic.json');
  const waiting = parseArgs(['pause', 'a', '--wait', '5']);
  assert.equal(waiting.waitSeconds, 5);
  const waitingDefault = parseArgs(['pause', 'a', '--wait']);
  assert.equal(waitingDefault.waitSeconds, 60);
  const imported = parseArgs([
    'import-codexmulti', '--store', '/synthetic/store', '--out', '/synthetic/out.json', '--dry-run',
  ]);
  assert.equal(imported.storePath, '/synthetic/store');
  assert.equal(imported.outPath, '/synthetic/out.json');
  assert.equal(imported.dryRun, true);
  await assert.rejects(main(['serve', 'unexpected'], {
    serveFromConfig: async () => assert.fail('serve must not start with extra arguments'),
  }), /invalid_arguments/);
});

test('offline login launches codex with only the selected account directory as CODEX_HOME', async () => {
  let spawnCall;
  const child = new EventEmitter();
  const resultPromise = runLogin({
    listen_host: '127.0.0.1', port: 1,
    accounts: [{ name: 'a', auth_file: '/synthetic/accounts/a/auth.json' }],
  }, 'a', {
    spawn: (command, args, options) => {
      spawnCall = { command, args, options };
      queueMicrotask(() => child.emit('exit', 0, null));
      return child;
    },
  });
  assert.deepEqual(await resultPromise, { login: 'complete', account: 'a' });
  assert.equal(spawnCall.command, 'codex');
  assert.deepEqual(spawnCall.args, ['login']);
  assert.equal(spawnCall.options.env.CODEX_HOME, '/synthetic/accounts/a');
});

test('online login performs pause, foreground login, reload, and READY transition', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a', 'b'] });
  const child = new EventEmitter();
  const resultPromise = runLogin({
    ...started.proxy.config,
    port: started.proxy.server.address().port,
  }, 'a', {
    spawn: () => {
      queueMicrotask(() => child.emit('exit', 0, null));
      return child;
    },
  });
  const result = await resultPromise;
  assert.equal(result.accounts.find(({ name }) => name === 'a').state, 'READY');
  const status = JSON.parse((await request(started.origin, '/_proxy/status')).body);
  assert.equal(status.accounts.find(({ name }) => name === 'a').state, 'READY');
});

test('online login polls a nonblocking pause until drain before spawning codex', async () => {
  const calls = [];
  let statusReads = 0;
  const child = new EventEmitter();
  const resultPromise = runLogin({
    listen_host: '127.0.0.1',
    port: 1,
    accounts: [{ name: 'a', auth_file: '/synthetic/accounts/a/auth.json' }],
  }, 'a', {
    controlRequest: async (_config, method, route) => {
      calls.push(`${method} ${route}`);
      if (method === 'GET') {
        statusReads += 1;
        return {
          accounts: [{ name: 'a', state: 'PAUSED', in_flight: statusReads < 3 ? 1 : 0 }],
        };
      }
      if (route.endsWith('/pause')) return { name: 'a', state: 'PAUSED', in_flight: 1 };
      return { accounts: [{ name: 'a', state: 'READY', in_flight: 0 }] };
    },
    sleep: async () => {},
    spawn: () => {
      assert.equal(statusReads, 3);
      queueMicrotask(() => child.emit('exit', 0, null));
      return child;
    },
  });
  const result = await resultPromise;
  assert.equal(result.accounts[0].state, 'READY');
  assert.deepEqual(calls, [
    'GET /_proxy/status',
    'POST /_proxy/accounts/a/pause',
    'GET /_proxy/status',
    'GET /_proxy/status',
    'POST /_proxy/accounts/a/reload',
  ]);
});

test('CLI status, switch, pause, and reload commands call the live control API', async (t) => {
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b'],
    labelsByName: { a: 'a@example.invalid', b: 'b@example.invalid' },
  });
  const config = {
    ...started.proxy.config,
    port: started.proxy.server.address().port,
  };
  async function invoke(args) {
    let output = '';
    await main(['--config', '/synthetic/config.json', ...args], {
      loadConfig: async () => config,
      stdout: { write: (chunk) => { output += chunk; } },
    });
    return JSON.parse(output);
  }
  assert.equal((await invoke(['status'])).active, 'a');
  const plain = await invoke(['status']);
  assert.equal(Object.hasOwn(plain.accounts[0], 'label'), false);
  assert.equal(Object.hasOwn(plain.accounts[0], 'auth_file'), false);
  const labelled = await invoke(['status', '--labels']);
  assert.equal(labelled.accounts[0].label, 'a@example.invalid');
  assert.equal(Object.hasOwn(labelled.accounts[0], 'auth_file'), false);
  assert.equal((await invoke(['switch', 'b'])).active, 'b');
  assert.deepEqual(await invoke(['pause', 'b']), { name: 'b', state: 'PAUSED', in_flight: 0 });
  assert.equal((await invoke(['reload', 'b'])).accounts.find(({ name }) => name === 'b').state, 'READY');
});

test('CLI pause --wait polls status until the account drains', async (t) => {
  let release;
  const held = new Promise((resolve) => { release = resolve; });
  let began;
  const startedRequest = new Promise((resolve) => { began = resolve; });
  const upstream = await startHttpServer(t, async (_req, res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('event: response.created\ndata: {"type":"response.created"}\n\n');
    began();
    await held;
    res.end('event: response.completed\ndata: {"type":"response.completed"}\n\n');
  });
  const started = await startTestProxy(t, { upstreamOrigin: upstream.origin, accountNames: ['a'] });
  const stream = request(started.origin, '/backend-api/codex/responses', { method: 'POST', body: '{}' });
  await startedRequest;
  let output = '';
  let completed = false;
  let waitingError;
  const waiting = main(['--config', '/synthetic/config.json', 'pause', 'a', '--wait', '2'], {
    loadConfig: async () => ({ ...started.proxy.config, port: started.proxy.server.address().port }),
    stdout: { write: (chunk) => { output += chunk; } },
  }).then(() => { completed = true; }, (error) => { waitingError = error; });
  await new Promise((resolve) => setTimeout(resolve, 50));
  assert.equal(completed, false);
  release();
  await stream;
  await waiting;
  if (waitingError) throw waitingError;
  const result = JSON.parse(output);
  assert.equal(result.accounts.find(({ name }) => name === 'a').in_flight, 0);
  assert.equal(result.accounts.find(({ name }) => name === 'a').state, 'PAUSED');
});

test('CLI refresh returns a safe result and a nonzero code on failure', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  let fail = false;
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a'],
    now,
    options: {
      refreshRequest: async () => {
        if (fail) throw new Error('synthetic_failure');
        return {
          access_token: jwt({ exp: nowSeconds + 10 * 86_400, token_name: 'cli-refresh' }),
          refresh_token: 'synthetic-refresh-cli',
        };
      },
    },
  });
  const config = { ...started.proxy.config, port: started.proxy.server.address().port };
  async function invoke() {
    let output = '';
    const exitCode = await main(['--config', '/synthetic/config.json', 'refresh', 'a'], {
      loadConfig: async () => config,
      stdout: { write: (chunk) => { output += chunk; } },
    });
    return { exitCode, output, value: JSON.parse(output) };
  }
  const succeeded = await invoke();
  assert.equal(succeeded.exitCode, 0);
  assert.equal(succeeded.value.result, 'ok');
  assert.doesNotMatch(succeeded.output, /synthetic-refresh|account_id|access_token|id_token|eyJ/);
  fail = true;
  const failed = await invoke();
  assert.equal(failed.exitCode, 1);
  assert.deepEqual(failed.value, { name: 'a', result: 'failed', access_expires_at: null });
});

test('CLI clear-cooldown calls the live control API and prints no credential material', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const upstream = await startHttpServer(t, (_req, res) => res.writeHead(204).end());
  const started = await startTestProxy(t, {
    upstreamOrigin: upstream.origin,
    accountNames: ['a', 'b'],
    labelsByName: { a: 'a@example.invalid' },
    now,
  });
  await started.proxy.failover.markCooldown('a', now + 5 * 86_400_000);
  const config = { ...started.proxy.config, port: started.proxy.server.address().port };
  let output = '';
  const exitCode = await main(['--config', '/synthetic/config.json', 'clear-cooldown', 'a'], {
    loadConfig: async () => config,
    stdout: { write: (chunk) => { output += chunk; } },
  });
  assert.equal(exitCode, 0);
  assert.deepEqual(JSON.parse(output), { name: 'a', state: 'READY', cooldown_until: null });
  assert.doesNotMatch(output,
    /Bearer|\beyJ|auth\.json|a@example\.invalid|synthetic-refresh|synthetic-account|account_id|access_token|id_token/i);
  assert.equal(started.proxy.failover.stateOf('a'), 'READY');
  await assert.rejects(
    main(['--config', '/synthetic/config.json', 'clear-cooldown'], {
      loadConfig: async () => config,
      stdout: { write: () => {} },
    }),
    /invalid_arguments/,
  );
});

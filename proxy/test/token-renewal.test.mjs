import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { writeFile } from 'node:fs/promises';
import {
  DEFAULT_RENEW_INTERVAL_MS,
  DEFAULT_RENEW_JITTER_MS,
  createProxy,
  nextTokenRenewalDelayMs,
} from '../src/server.mjs';
import {
  jwt,
  makeTempDir,
  syntheticAuth,
  writeAccountAuth,
} from './helpers.mjs';

async function createTestProxy(t, { now, authByName, options = {} }) {
  const root = await makeTempDir(t);
  const accounts = [];
  for (const [name, auth] of Object.entries(authByName)) {
    accounts.push({ name, auth_file: await writeAccountAuth(root, name, auth) });
  }
  const config = {
    listen_host: '127.0.0.1',
    port: 0,
    mode: 'failover',
    accounts,
    upstream_chatgpt_base_url: 'http://127.0.0.1:1/backend-api/',
    upstream_openai_base_url: 'http://127.0.0.1:1/backend-api/codex',
    allow_insecure_upstream: true,
    state_file: path.join(root, 'state/state.json'),
    log_file: null,
  };
  return await createProxy(config, { now: () => now, ...options });
}

test('proactive renewal refreshes only accounts expiring within 48 hours and exposes safe status', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const calls = [];
  const events = [];
  const fakeTokenEndpoint = async (_url, refreshToken) => {
    calls.push(refreshToken);
    const name = refreshToken.endsWith('-a') ? 'a' : 'c';
    return {
      access_token: jwt({ exp: nowSeconds + 10 * 86_400, token_name: `renewed-${name}` }),
      refresh_token: `rotated-refresh-${name}`,
    };
  };
  const proxy = await createTestProxy(t, {
    authByName: {
      a: syntheticAuth('a', nowSeconds + 48 * 3600),
      b: syntheticAuth('b', nowSeconds + 48 * 3600 + 1),
      c: syntheticAuth('c', nowSeconds + 3600),
    },
    now,
    options: {
      refreshRequest: fakeTokenEndpoint,
      logger: (event) => events.push(event),
    },
  });

  await proxy.runTokenRenewalCycle();

  assert.deepEqual(calls, ['synthetic-refresh-a', 'synthetic-refresh-c']);
  const status = await proxy.statusPayload();
  assert.deepEqual(status.accounts.map(({ name, token_refresh }) => ({ name, token_refresh })), [
    {
      name: 'a',
      token_refresh: {
        last_ok_at: new Date(now).toISOString(),
        last_error: null,
        next_attempt_at: null,
      },
    },
    {
      name: 'b',
      token_refresh: { last_ok_at: null, last_error: null, next_attempt_at: null },
    },
    {
      name: 'c',
      token_refresh: {
        last_ok_at: new Date(now).toISOString(),
        last_error: null,
        next_attempt_at: null,
      },
    },
  ]);
  assert.deepEqual(events.map(({ event, account_name }) => ({ event, account_name })), [
    { event: 'token_renewed', account_name: 'a' },
    { event: 'token_renewed', account_name: 'c' },
  ]);
  assert.doesNotMatch(JSON.stringify(events), /synthetic-refresh|rotated-refresh|eyJ|access_token|refresh_token/i);
});

test('proactive renewal skips an expiring account while it has an in-flight request', async (t) => {
  const now = Date.UTC(2030, 0, 1);
  let refreshes = 0;
  const proxy = await createTestProxy(t, {
    authByName: { a: syntheticAuth('a', Math.floor(now / 1000) + 3600) },
    now,
    options: {
      initialInFlight: new Map([['a', 1]]),
      refreshRequest: async () => {
        refreshes += 1;
        return { access_token: jwt({ exp: Math.floor(now / 1000) + 10 * 86_400 }) };
      },
    },
  });
  await proxy.runTokenRenewalCycle();

  assert.equal(refreshes, 0);
  assert.equal((await proxy.statusPayload()).accounts[0].in_flight, 1);
});

test('proactive renewal backs off failures and marks the account invalid without logging values', async (t) => {
  let clock = Date.UTC(2030, 0, 1);
  const initial = clock;
  const events = [];
  let refreshes = 0;
  const proxy = await createTestProxy(t, {
    authByName: { a: syntheticAuth('a', Math.floor(clock / 1000) + 3600) },
    now: clock,
    options: {
      now: () => clock,
      refreshRequest: async () => {
        refreshes += 1;
        throw new Error('refresh_rejected');
      },
      logger: (event) => events.push(event),
    },
  });

  await proxy.runTokenRenewalCycle();
  let account = (await proxy.statusPayload()).accounts[0];
  assert.equal(refreshes, 1);
  assert.equal(account.state, 'INVALID');
  assert.equal(account.token_refresh.last_error, 'rejected');
  assert.equal(account.token_refresh.next_attempt_at, new Date(initial + 3600_000).toISOString());

  await proxy.runTokenRenewalCycle();
  assert.equal(refreshes, 1);

  clock = initial + 3600_000;
  await proxy.runTokenRenewalCycle();
  account = (await proxy.statusPayload()).accounts[0];
  assert.equal(refreshes, 2);
  assert.equal(account.state, 'INVALID');
  assert.equal(account.token_refresh.next_attempt_at, new Date(clock + 2 * 3600_000).toISOString());
  assert.deepEqual(events.map(({ event, error_kind }) => ({ event, error_kind })), [
    { event: 'token_renew_failed', error_kind: 'rejected' },
    { event: 'token_renew_failed', error_kind: 'rejected' },
  ]);
  assert.doesNotMatch(JSON.stringify(events), /synthetic-refresh|synthetic-account|eyJ|access_token|refresh_token/i);
});

test('proactive renewal adopts a fresh disk rotation after backoff and clears invalid status', async (t) => {
  let clock = Date.UTC(2030, 0, 1);
  let refreshes = 0;
  const proxy = await createTestProxy(t, {
    authByName: { a: syntheticAuth('a', Math.floor(clock / 1000) + 3600) },
    now: clock,
    options: {
      now: () => clock,
      refreshRequest: async () => {
        refreshes += 1;
        throw new Error('refresh_rejected');
      },
    },
  });

  await proxy.runTokenRenewalCycle();
  clock += 3600_000;
  const fresh = syntheticAuth('a', Math.floor(clock / 1000) + 10 * 86_400);
  await writeFile(proxy.config.accounts[0].auth_file, `${JSON.stringify(fresh, null, 2)}\n`, { mode: 0o600 });

  await proxy.runTokenRenewalCycle();

  const account = (await proxy.statusPayload()).accounts[0];
  assert.equal(refreshes, 1);
  assert.equal(account.state, 'READY', JSON.stringify(account));
  assert.deepEqual(account.token_refresh, {
    last_ok_at: null,
    last_error: null,
    next_attempt_at: null,
  });
});

test('renewal cadence jitter stays within thirty minutes of six hours', () => {
  assert.equal(nextTokenRenewalDelayMs(() => 0), DEFAULT_RENEW_INTERVAL_MS - DEFAULT_RENEW_JITTER_MS);
  assert.equal(nextTokenRenewalDelayMs(() => 0.5), DEFAULT_RENEW_INTERVAL_MS);
  assert.equal(nextTokenRenewalDelayMs(() => 1), DEFAULT_RENEW_INTERVAL_MS + DEFAULT_RENEW_JITTER_MS);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { chmod, readFile, symlink, writeFile } from 'node:fs/promises';
import {
  AccountRegistry,
  DEFAULT_REFRESH_URL,
  DEFAULT_REFRESH_SKEW_SECONDS,
  REFRESH_CLIENT_ID,
  atomicWriteJson,
  parseJwtExp,
  readAuthFile,
} from '../src/accounts.mjs';
import { jwt, makeTempDir, syntheticAuth, writeAccountAuth } from './helpers.mjs';

test('parseJwtExp handles valid, missing, and malformed JWT payloads', () => {
  assert.equal(DEFAULT_REFRESH_URL, 'https://auth.openai.com/oauth/token');
  assert.equal(REFRESH_CLIENT_ID, 'app_EMoamEEZ73f0CkXaXp7hrann');
  assert.equal(DEFAULT_REFRESH_SKEW_SECONDS, 172_800);
  assert.equal(parseJwtExp(jwt({ exp: 1234 })), 1234);
  assert.equal(parseJwtExp(jwt({ sub: 'synthetic' })), null);
  assert.equal(parseJwtExp('not-a-jwt'), null);
});

test('lazy refresh triggers at the exp skew boundary and rotates tokens atomically', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds + DEFAULT_REFRESH_SKEW_SECONDS));
  let refreshes = 0;
  const rotated = jwt({ exp: nowSeconds + 10 * 86_400, token_name: 'rotated' });
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => {
      refreshes += 1;
      return { access_token: rotated, refresh_token: 'synthetic-refresh-rotated', id_token: jwt({ fixture: true }) };
    },
  });
  await registry.initialize();
  const credentials = await registry.ensureFresh('a');
  assert.equal(credentials.accessToken, rotated);
  assert.equal(refreshes, 1);
  const saved = JSON.parse(await readFile(authFile, 'utf8'));
  assert.equal(saved.tokens.refresh_token, 'synthetic-refresh-rotated');
  assert.deepEqual(saved.fixture_marker, { preserve: true });
});

test('file identity change reloads externally updated auth before request selection', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds + 10 * 86_400));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => { refreshes += 1; throw new Error('must not refresh'); },
  });
  await registry.initialize();
  const externallyUpdated = syntheticAuth('a', nowSeconds + 11 * 86_400, {
    tokens: { access_token: jwt({ exp: nowSeconds + 11 * 86_400, token_name: 'external-update' }) },
  });
  await writeFile(authFile, `${JSON.stringify(externallyUpdated, null, 2)}\n`, { mode: 0o600 });
  const credentials = await registry.ensureFresh('a');
  assert.equal(parseJwtExp(credentials.accessToken), nowSeconds + 11 * 86_400);
  assert.equal(refreshes, 0);
});

test('refresh failure adopts a concurrently rotated refresh chain without retrying', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds + 3600));
  const externallyRefreshedAccess = jwt({ exp: nowSeconds + 10 * 86_400, token_name: 'external-refresh' });
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => {
      refreshes += 1;
      const disk = JSON.parse(await readFile(authFile, 'utf8'));
      disk.tokens.access_token = externallyRefreshedAccess;
      disk.tokens.refresh_token = 'synthetic-refresh-external-rotation';
      await atomicWriteJson(authFile, disk);
      throw new Error('synthetic_stale_refresh_chain');
    },
  });
  await registry.initialize();
  const credentials = await registry.ensureFresh('a');
  assert.equal(credentials.accessToken, externallyRefreshedAccess);
  assert.equal(refreshes, 1);
  assert.equal((await registry.ensureFresh('a')).accessToken, externallyRefreshedAccess);
  assert.equal(refreshes, 1);
});

test('forceRefresh refreshes a healthy token and reports the new expiry', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds + 10 * 86_400));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => {
      refreshes += 1;
      return { access_token: jwt({ exp: nowSeconds + 11 * 86_400, token_name: 'forced-refresh' }) };
    },
  });
  await registry.initialize();
  const credentials = await registry.forceRefresh('a');
  assert.equal(credentials.expiresAt, nowSeconds + 11 * 86_400);
  assert.equal(refreshes, 1);
});

test('duplicate account identities produce names-only warnings without blocking load', async (t) => {
  const root = await makeTempDir(t);
  const sharedIdentity = 'synthetic-shared-identity';
  const first = await writeAccountAuth(root, 'a', syntheticAuth('a', 4_102_444_800, {
    tokens: { account_id: sharedIdentity },
  }));
  const second = await writeAccountAuth(root, 'b', syntheticAuth('b', 4_102_444_800, {
    tokens: { account_id: sharedIdentity },
  }));
  const registry = new AccountRegistry([
    { name: 'a', auth_file: first },
    { name: 'b', auth_file: second },
  ]);
  await registry.initialize();
  const warnings = registry.duplicateIdentityNames();
  assert.deepEqual(warnings, [{ first: 'a', duplicate: 'b' }]);
  assert.doesNotMatch(JSON.stringify(warnings), /synthetic-shared-identity/);
});

test('concurrent lazy refresh calls share a single refresh under the account mutex', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds - 1));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => {
      refreshes += 1;
      await new Promise((resolve) => setTimeout(resolve, 25));
      return { access_token: jwt({ exp: nowSeconds + 10 * 86_400, generation: refreshes }) };
    },
  });
  await registry.initialize();
  const values = await Promise.all(Array.from({ length: 8 }, () => registry.ensureFresh('a')));
  assert.equal(refreshes, 1);
  assert.equal(new Set(values.map((value) => value.accessToken)).size, 1);
});

test('401 recovery uses a disk-reloaded token without refreshing when another writer changed it', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const oldToken = jwt({ exp: Math.floor(now / 1000) + 3600, generation: 'old' });
  const nextToken = jwt({ exp: Math.floor(now / 1000) + 3600, generation: 'next' });
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', Math.floor(now / 1000) + 3600, {
    tokens: { access_token: oldToken },
  }));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => { refreshes += 1; throw new Error('must not run'); },
  });
  await registry.initialize();
  const disk = JSON.parse(await readFile(authFile, 'utf8'));
  disk.tokens.access_token = nextToken;
  await atomicWriteJson(authFile, disk);
  const credentials = await registry.recover401('a', oldToken);
  assert.equal(credentials.accessToken, nextToken);
  assert.equal(refreshes, 0);
});

test('401 recovery refreshes once when the disk token is unchanged', async (t) => {
  const root = await makeTempDir(t);
  const now = Date.UTC(2030, 0, 1);
  const nowSeconds = Math.floor(now / 1000);
  const oldToken = jwt({ exp: nowSeconds + 3600, generation: 'old' });
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', nowSeconds + 3600, {
    tokens: { access_token: oldToken },
  }));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    now: () => now,
    refreshRequest: async () => {
      refreshes += 1;
      return { access_token: jwt({ exp: nowSeconds + 7200, generation: 'new' }) };
    },
  });
  await registry.initialize();
  assert.notEqual((await registry.recover401('a', oldToken)).accessToken, oldToken);
  assert.equal(refreshes, 1);
});

test('unparseable refreshed access JWT makes the account refresh fail once', async (t) => {
  const root = await makeTempDir(t);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', 1, {
    tokens: { access_token: 'invalid.jwt.value' },
  }));
  let refreshes = 0;
  const registry = new AccountRegistry([{ name: 'a', auth_file: authFile }], {
    refreshRequest: async () => { refreshes += 1; return { access_token: 'still.invalid.value' }; },
  });
  await registry.initialize();
  await assert.rejects(registry.ensureFresh('a'), /credential_refresh_failed/);
  assert.equal(refreshes, 1);
});

test('atomic write failure preserves the prior auth file and removes the temporary file', async (t) => {
  const root = await makeTempDir(t);
  const file = path.join(root, 'state.json');
  await writeFile(file, '{"before":true}\n', { mode: 0o600 });
  await assert.rejects(atomicWriteJson(file, { after: true }, {
    beforeRename: async () => { throw new Error('synthetic_failure'); },
  }), /synthetic_failure/);
  assert.equal(await readFile(file, 'utf8'), '{"before":true}\n');
  const entries = await (await import('node:fs/promises')).readdir(root);
  assert.deepEqual(entries, ['state.json']);
});

test('credential permissions, symlinks, and traversal are rejected', async (t) => {
  const root = await makeTempDir(t);
  const authFile = await writeAccountAuth(root, 'a', syntheticAuth('a', 4_102_444_800));
  await chmod(authFile, 0o644);
  await assert.rejects(readAuthFile(authFile), /credential_file_not_private/);
  await chmod(authFile, 0o600);
  const link = path.join(root, 'a', 'auth-link.json');
  await symlink(authFile, link);
  await assert.rejects(readAuthFile(link), /invalid_auth_file/);
  assert.throws(() => new AccountRegistry([{ name: 'a', auth_file: `${root}/../auth.json` }]), /auth_path_escape/);
});

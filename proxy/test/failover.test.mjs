import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { FailoverManager, AccountState, calculateCooldownUntil } from '../src/failover.mjs';
import { makeTempDir } from './helpers.mjs';
import { readFile, writeFile } from 'node:fs/promises';

test('selector follows cursor order and skips PAUSED and INVALID accounts', async () => {
  const manager = new FailoverManager(['a', 'b', 'c']);
  await manager.initialize();
  assert.equal(await manager.selectReady(), 'a');
  await manager.switchTo('b');
  assert.equal(await manager.selectReady(), 'b');
  await manager.pause('b');
  assert.equal(await manager.selectReady(), 'c');
  await manager.markInvalid('c');
  assert.equal(await manager.selectReady(), 'a');
});

test('expired cooldown returns to READY and earliest cooldown is deterministic', async () => {
  let now = Date.UTC(2030, 0, 1);
  const manager = new FailoverManager(['a', 'b', 'c'], { now: () => now });
  await manager.initialize();
  await manager.markCooldown('a', now + 5_000);
  await manager.markCooldown('b', now + 2_000);
  await manager.markCooldown('c', now + 2_000);
  assert.equal(await manager.earliestCooldown(), 'b');
  now += 2_001;
  await manager.expireCooldowns();
  assert.equal(manager.stateOf('b'), AccountState.READY);
  assert.equal(manager.stateOf('c'), AccountState.READY);
  assert.equal(manager.stateOf('a'), AccountState.COOLDOWN);
});

test('cooldown reset source priority is body, then active header family, then default, with margin', () => {
  const now = 1_900_000_000_000;
  const nowSeconds = now / 1000;
  assert.equal(calculateCooldownUntil({
    body: { error: { resets_at: nowSeconds + 50 } },
    headers: {
      'x-codex-active-limit': 'team',
      'x-codex-rate-limit-reached-type': 'secondary',
      'x-team-secondary-reset-at': String(nowSeconds + 100),
    }, now, defaultSeconds: 300, marginSeconds: 7,
  }), (nowSeconds + 57) * 1000);
  assert.equal(calculateCooldownUntil({
    body: { error: {} },
    headers: {
      'x-codex-active-limit': 'team',
      'x-codex-rate-limit-reached-type': 'secondary',
      'x-team-secondary-reset-at': String(nowSeconds + 100),
    }, now, defaultSeconds: 300, marginSeconds: 7,
  }), (nowSeconds + 107) * 1000);
  assert.equal(calculateCooldownUntil({ body: {}, headers: {}, now, defaultSeconds: 300, marginSeconds: 7 }),
    (nowSeconds + 307) * 1000);
});

test('state restores cursor, cooldown, pause, and invalid status across restart', async (t) => {
  const root = await makeTempDir(t);
  const stateFile = path.join(root, 'state/state.json');
  const now = Date.UTC(2030, 0, 1);
  const first = new FailoverManager(['a', 'b', 'c'], { stateFile, now: () => now });
  await first.initialize();
  await first.switchTo('c');
  await first.markCooldown('a', now + 60_000);
  await first.pause('b');
  await first.markInvalid('c');
  const second = new FailoverManager(['a', 'b', 'c'], { stateFile, now: () => now });
  await second.initialize();
  assert.equal(second.snapshot().cursor, 'c');
  assert.equal(second.stateOf('a'), AccountState.COOLDOWN);
  assert.equal(second.stateOf('b'), AccountState.PAUSED);
  assert.equal(second.stateOf('c'), AccountState.INVALID);
  await second.reloadReady('c');
  assert.equal(second.stateOf('c'), AccountState.READY);
});

test('state persists auth_file and restores all state by exact auth path after renames', async (t) => {
  const root = await makeTempDir(t);
  const stateFile = path.join(root, 'state/state.json');
  const now = Date.UTC(2030, 0, 1);
  const original = [
    { name: 'a', auth_file: '/synthetic/identity-a/auth.json' },
    { name: 'b', auth_file: '/synthetic/identity-b/auth.json' },
    { name: 'c', auth_file: '/synthetic/identity-c/auth.json' },
  ];
  const first = new FailoverManager(original, { stateFile, now: () => now });
  await first.initialize();
  await first.markCooldown('a', now + 60_000);
  await first.pause('b');
  await first.markInvalid('c');
  await first.switchTo('c');
  const persisted = JSON.parse(await readFile(stateFile, 'utf8'));
  assert.equal(persisted.accounts.a.auth_file, original[0].auth_file);

  const renamed = [
    { name: 'x', auth_file: original[2].auth_file },
    { name: 'y', auth_file: original[0].auth_file },
    { name: 'z', auth_file: original[1].auth_file },
  ];
  const second = new FailoverManager(renamed, { stateFile, now: () => now });
  await second.initialize();
  assert.equal(second.snapshot().cursor, 'x');
  assert.equal(second.stateOf('x'), AccountState.INVALID);
  assert.equal(second.stateOf('y'), AccountState.COOLDOWN);
  assert.equal(second.stateOf('z'), AccountState.PAUSED);
});

test('legacy state without auth_file loads once by name and is rewritten in the new form', async (t) => {
  const root = await makeTempDir(t);
  const stateFile = path.join(root, 'legacy-state.json');
  const now = Date.UTC(2030, 0, 1);
  await writeFile(stateFile, `${JSON.stringify({
    version: 1,
    cursor: 'b',
    accounts: {
      a: { paused: true, cooldown_until: null, reason: 'operator_paused' },
      b: { paused: false, cooldown_until: null, reason: null },
    },
    updated_at: new Date(now).toISOString(),
  }, null, 2)}\n`, { mode: 0o600 });
  const accounts = [
    { name: 'a', auth_file: '/synthetic/identity-a/auth.json' },
    { name: 'b', auth_file: '/synthetic/identity-b/auth.json' },
  ];
  const manager = new FailoverManager(accounts, { stateFile, now: () => now });
  await manager.initialize();
  assert.equal(manager.snapshot().cursor, 'b');
  assert.equal(manager.stateOf('a'), AccountState.PAUSED);
  const rewritten = JSON.parse(await readFile(stateFile, 'utf8'));
  assert.equal(rewritten.accounts.a.auth_file, accounts[0].auth_file);
  assert.equal(rewritten.accounts.b.auth_file, accounts[1].auth_file);
});

test('concurrent limit transitions do not lose either cooldown update', async (t) => {
  const root = await makeTempDir(t);
  const manager = new FailoverManager(['a', 'b'], { stateFile: path.join(root, 'state.json') });
  await manager.initialize();
  await Promise.all([
    manager.markCooldown('a', Date.now() + 20_000),
    manager.markCooldown('b', Date.now() + 30_000),
  ]);
  assert.equal(manager.stateOf('a'), AccountState.COOLDOWN);
  assert.equal(manager.stateOf('b'), AccountState.COOLDOWN);
});

test('corrupt persisted state fails closed instead of bypassing cooldown', async (t) => {
  const root = await makeTempDir(t);
  const stateFile = path.join(root, 'state.json');
  await (await import('node:fs/promises')).writeFile(stateFile, '{broken', { mode: 0o600 });
  const manager = new FailoverManager(['a'], { stateFile });
  await assert.rejects(manager.initialize(), /invalid_state_file/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { FailoverManager } from '../src/failover.mjs';
import { makeTempDir } from './helpers.mjs';

const accounts = [
  { name: 'a', auth_file: '/test/a/auth.json', auto_select_enabled: true },
  { name: 'b', auth_file: '/test/b/auth.json', auto_select_enabled: false },
  { name: 'c', auth_file: '/test/c/auth.json', auto_select_enabled: true },
];

test('manual-only accounts are skipped by automatic failover and cooldown probes', async () => {
  const manager = new FailoverManager(accounts);
  await manager.markCooldown('a', Date.now() + 60_000);
  assert.equal(await manager.selectReady(), 'c');
  await manager.markCooldown('b', Date.now() + 5_000);
  await manager.markCooldown('c', Date.now() + 90_000);
  assert.equal(await manager.earliestCooldown(), 'a');
});

test('explicit selection uses a manual-only account without enabling automatic selection', async () => {
  const manager = new FailoverManager(accounts);
  await manager.switchTo('b');
  assert.equal(await manager.selectReady(), 'b');
  assert.equal(manager.snapshot().accounts.b.auto_select_enabled, false);
  await manager.returnToAutomatic();
  assert.equal(await manager.selectReady(), 'c');
});

test('quota failure clears manual selection permanently, including after reset and reload', async () => {
  let now = Date.UTC(2030, 0, 1);
  const manager = new FailoverManager(accounts, { now: () => now });
  await manager.switchTo('b');
  await manager.markCooldown('b', now + 10_000);
  assert.equal(await manager.selectReady(), 'c');
  now += 20_000;
  await manager.reloadReady('b');
  assert.equal(await manager.selectReady(), 'c');
  assert.equal(manager.snapshot().accounts.b.auto_select_enabled, false);
});

test('automatic exclusion drains future work while preserving an explicit selection', async () => {
  const manager = new FailoverManager(accounts);
  await manager.setAutoSelect('a', false);
  assert.equal(await manager.selectReady(), 'c');
  await manager.switchTo('c');
  await manager.setAutoSelect('c', false);
  assert.equal(await manager.selectReady(), 'c');
  await manager.returnToAutomatic();
  assert.equal(await manager.selectReady(), null);
  assert.equal(await manager.earliestCooldown(), null);
});

test('manual policy and explicit selection survive restart and identity renaming', async (t) => {
  const root = await makeTempDir(t);
  const stateFile = path.join(root, 'state.json');
  const first = new FailoverManager(accounts, { stateFile });
  await first.initialize();
  await first.switchTo('b');
  const renamed = accounts.map((account) => ({ ...account, name: `${account.name}-new` }));
  const second = new FailoverManager(renamed, { stateFile });
  await second.initialize();
  assert.equal(await second.selectReady(), 'b-new');
  assert.equal(second.snapshot().selection_source, 'manual');
  await second.returnToAutomatic();
  assert.equal(await second.selectReady(), 'c-new');
});

test('manual switching rejects unusable accounts without changing the current selection', async () => {
  const manager = new FailoverManager(accounts);
  await manager.pause('b');
  await assert.rejects(manager.switchTo('b'), /account_not_ready/);
  assert.equal(await manager.selectReady(), 'a');
  await manager.reloadReady('b');
  assert.equal(manager.stateOf('b'), 'PAUSED');
  await manager.resume('b');
  await manager.switchTo('b');
  assert.equal(await manager.selectReady(), 'b');
});

test('an old account failure cannot discard a newer explicit selection', async () => {
  const manager = new FailoverManager(accounts);
  await manager.switchTo('a');
  const revision = manager.snapshot().selection_revision;
  await manager.switchTo('b');
  await manager.markCooldown('a', Date.now() + 60_000, revision);
  assert.equal(await manager.selectReady(), 'b');
});

test('legacy paused accounts remain paused and become manual-only without inferring manual intent', async () => {
  const manager = new FailoverManager([{ name: 'renamed', auth_file: '/test/a/auth.json' }]);
  await manager.initializeFrom({
    version: 1, cursor: 'a', updated_at: new Date().toISOString(),
    accounts: { a: { auth_file: '/test/a/auth.json', paused: true, cooldown_until: null, reason: 'operator_paused' } },
  });
  assert.equal(manager.snapshot().accounts.renamed.auto_select_enabled, false);
  assert.equal(manager.snapshot().selection_source, 'automatic');
  await manager.resume('renamed');
  assert.equal(await manager.active(), null);
  await manager.switchTo('renamed');
  assert.equal(await manager.active(), 'renamed');
});

test('failed policy persistence does not report or apply the new value', async () => {
  const manager = new FailoverManager(accounts, {
    stateFile: '/synthetic/state.json', writer: async () => { throw new Error('write_failed'); },
  });
  await assert.rejects(manager.setAutoSelect('a', false), /write_failed/);
  assert.equal(await manager.active(), 'a');
  assert.equal(manager.snapshot().accounts.a.auto_select_enabled, true);
});

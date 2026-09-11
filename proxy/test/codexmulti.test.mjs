import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { access, chmod, mkdir, readFile, writeFile } from 'node:fs/promises';
import { atomicWriteJson } from '../src/accounts.mjs';
import { main } from '../src/cli.mjs';
import { formatImportTable, importCodexMulti } from '../src/codexmulti.mjs';
import { makeTempDir, syntheticAuth, writeAccountAuth } from './helpers.mjs';

const KEYS = [
  'codex-00000000000000000000000000000001',
  'codex-00000000000000000000000000000002',
  'codex-00000000000000000000000000000003',
];

async function buildStore(testContext, options = {}) {
  const root = await makeTempDir(testContext);
  const store = path.join(root, 'store');
  await mkdir(store, { recursive: true, mode: 0o700 });
  const exp = 4_102_444_800;
  const sharedIdentity = options.duplicateIdentity ? 'synthetic-shared-account' : null;
  await writeAccountAuth(path.join(store, 'accounts', KEYS[0]), 'codex', syntheticAuth('one', exp, {
    tokens: sharedIdentity ? { account_id: sharedIdentity } : {},
  }));
  const secondAuth = await writeAccountAuth(path.join(store, 'accounts', KEYS[1]), 'codex', syntheticAuth('two', exp, {
    tokens: sharedIdentity ? { account_id: sharedIdentity } : {},
  }));
  const metadata = {
    schema_version: 1,
    accounts: [
      {
        id: 'synthetic-entry-1', provider: 'codex', provider_email: 'one@example.invalid',
        storage_key: KEYS[0], auth_state: 'connected', enabled: true,
      },
      {
        id: 'synthetic-claude', provider: 'claude', provider_email: 'skip@example.invalid',
        storage_key: 'claude-synthetic', auth_state: 'connected', enabled: true,
      },
      {
        id: 'synthetic-entry-2', provider: 'codex', provider_email: 'two@example.invalid',
        storage_key: KEYS[1], auth_state: 'connected', enabled: true,
      },
      {
        id: 'synthetic-disabled', provider: 'codex', provider_email: 'disabled@example.invalid',
        storage_key: KEYS[2], auth_state: 'connected', enabled: false,
      },
    ],
  };
  await writeFile(path.join(store, 'accounts.json'), `${JSON.stringify(metadata, null, 2)}\n`, { mode: 0o600 });
  return { root, store, secondAuth };
}

test('CodexMulti dry-run discovers eligible accounts in source order without writing', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  const result = await importCodexMulti({ store: fixture.store, out, dryRun: true });
  assert.equal(result.ok, true);
  assert.equal(result.wrote, false);
  assert.deepEqual(result.rows.map(({ name, validation }) => ({ name, validation })), [
    { name: 'codex-1', validation: 'ok' },
    { name: 'codex-2', validation: 'ok' },
  ]);
  await assert.rejects(access(out), /ENOENT/);
  const table = formatImportTable(result.rows);
  assert.match(table, /NAME\s+LABEL\s+ACCESS EXPIRES AT\s+VALIDATION/);
  assert.doesNotMatch(table, /auth\.json|synthetic-refresh|synthetic-account|eyJ/);
});

test('CodexMulti import replaces only accounts and preserves existing config keys', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  await mkdir(path.dirname(out), { recursive: true, mode: 0o700 });
  await atomicWriteJson(out, {
    listen_host: '127.0.0.1',
    port: 8989,
    mode: 'failover',
    accounts: [{ name: 'old', auth_file: '/synthetic/old/auth.json' }],
    upstream_chatgpt_base_url: 'https://chatgpt.com/backend-api/',
    upstream_openai_base_url: 'https://chatgpt.com/backend-api/codex',
    request_body_limit_bytes: 67_108_864,
    token_refresh_skew_seconds: 172_800,
    default_cooldown_seconds: 1800,
    cooldown_safety_margin_seconds: 60,
    allow_insecure_upstream: false,
    preserved_extension: { enabled: true },
  });
  const result = await importCodexMulti({ store: fixture.store, out });
  assert.equal(result.ok, true);
  assert.equal(result.wrote, true);
  const saved = JSON.parse(await readFile(out, 'utf8'));
  assert.equal(saved.port, 8989);
  assert.deepEqual(saved.preserved_extension, { enabled: true });
  assert.deepEqual(saved.accounts.map(({ name, label }) => ({ name, label })), [
    { name: 'codex-1', label: 'one@example.invalid' },
    { name: 'codex-2', label: 'two@example.invalid' },
  ]);
  assert.ok(saved.accounts.every((account) => account.auth_file.startsWith(fixture.store)));
});

test('new CodexMulti config uses 48-hour skew and duplicate identities only warn', async (t) => {
  const fixture = await buildStore(t, { duplicateIdentity: true });
  const out = path.join(fixture.root, 'output/config.json');
  const result = await importCodexMulti({ store: fixture.store, out });
  assert.equal(result.ok, true);
  assert.equal(result.warnings.length, 1);
  assert.match(result.warnings[0], /codex-1,codex-2/);
  assert.doesNotMatch(result.warnings[0], /synthetic-shared-account/);
  const saved = JSON.parse(await readFile(out, 'utf8'));
  assert.equal(saved.token_refresh_skew_seconds, 172_800);
});

test('invalid CodexMulti auth permissions fail validation and block config writes', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  await chmod(fixture.secondAuth, 0o644);
  const result = await importCodexMulti({ store: fixture.store, out });
  assert.equal(result.ok, false);
  assert.equal(result.rows[1].validation, 'failed');
  assert.equal(result.wrote, false);
  await assert.rejects(access(out), /ENOENT/);
});

test('unparseable CodexMulti access JWT blocks config writes', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  const auth = JSON.parse(await readFile(fixture.secondAuth, 'utf8'));
  auth.tokens.access_token = 'synthetic-not-a-jwt';
  await atomicWriteJson(fixture.secondAuth, auth);
  const result = await importCodexMulti({ store: fixture.store, out });
  assert.equal(result.ok, false);
  assert.equal(result.rows[1].validation, 'failed');
  assert.equal(result.rows[1].accessExpiresAt, null);
  await assert.rejects(access(out), /ENOENT/);
});

test('import-codexmulti CLI prints only the validation table in dry-run mode', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  let stdout = '';
  let stderr = '';
  const exitCode = await main([
    'import-codexmulti', '--store', fixture.store, '--out', out, '--dry-run',
  ], {
    stdout: { write: (chunk) => { stdout += chunk; } },
    stderr: { write: (chunk) => { stderr += chunk; } },
  });
  assert.equal(exitCode, 0);
  assert.equal(stderr, '');
  assert.match(stdout, /codex-1/);
  assert.match(stdout, /one@example\.invalid/);
  assert.doesNotMatch(stdout, /auth\.json|synthetic-refresh|synthetic-account|account_id|access_token|id_token|eyJ/);
  await assert.rejects(access(out), /ENOENT/);
});

test('import-codexmulti exits within 3s and writes its config while stdin stays open', async (t) => {
  const fixture = await buildStore(t);
  const out = path.join(fixture.root, 'output/config.json');
  const binary = path.join(
    path.dirname(path.dirname(fileURLToPath(import.meta.url))), 'bin/codexmulti-proxy',
  );
  const child = spawn(process.execPath, [
    binary, 'import-codexmulti', '--store', fixture.store, '--out', out,
  ], { stdio: ['pipe', 'pipe', 'pipe'] });
  t.after(() => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  });

  child.stdin.on('error', () => {});
  child.stdin.write('synthetic stdin that is never terminated\n');
  let stdout = '';
  let stderr = '';
  let configWrittenBeforeFirstOutput = null;
  child.stdout.on('data', (chunk) => {
    if (configWrittenBeforeFirstOutput === null) configWrittenBeforeFirstOutput = existsSync(out);
    stdout += chunk;
  });
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  const exit = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error('cli_did_not_exit_within_3s'));
    }, 3_000);
    child.once('exit', (code, signal) => { clearTimeout(timer); resolve({ code, signal }); });
    child.once('error', (error) => { clearTimeout(timer); reject(error); });
  });
  assert.deepEqual(exit, { code: 0, signal: null });
  assert.equal(stderr, '');
  assert.match(stdout, /codex-1/);
  assert.equal(configWrittenBeforeFirstOutput, true);
  const saved = JSON.parse(await readFile(out, 'utf8'));
  assert.deepEqual(saved.accounts.map(({ name }) => name), ['codex-1', 'codex-2']);
});

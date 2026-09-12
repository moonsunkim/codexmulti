import assert from 'node:assert/strict';
import { randomBytes, createPrivateKey, createPublicKey, verify } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const signer = path.join(root, '.build/artifacts/sparkle/Sparkle/bin/sign_update');

test('real Sparkle signatures reject archive tampering, feed tampering and mismatched keys', async () => {
  const temporary = await mkdtemp(path.join(os.tmpdir(), 'codexmulti-appcast-test-'));
  try {
    const app = path.join(temporary, 'CodexMulti.app');
    await mkdir(path.join(app, 'Contents/Resources'), { recursive: true });
    const seed = randomBytes(32);
    const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]), format: 'der', type: 'pkcs8' });
    const publicKey = createPublicKey(privateKey);
    const info = path.join(app, 'Contents/Info.plist');
    execFileSync('/usr/bin/plutil', ['-create', 'xml1', info]);
    const values = { SUPublicEDKey: publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64'),
      CFBundleVersion: '202609120001', CFBundleShortVersionString: '0.0.1' };
    for (const [key, value] of Object.entries(values)) execFileSync('/usr/bin/plutil', ['-insert', key, '-string', value, info]);
    execFileSync('/usr/bin/plutil', ['-insert', 'SURequireSignedFeed', '-bool', 'true', info]);
    execFileSync('/usr/bin/plutil', ['-insert', 'SUVerifyUpdateBeforeExtraction', '-bool', 'false', info]);
    await writeFile(path.join(app, 'Contents/Resources/runtime-manifest.json'), JSON.stringify({ runtime_id: 'a'.repeat(64) }));
    const key = path.join(temporary, 'private-seed');
    await writeFile(key, seed.toString('base64'), { mode: 0o600 });
    const archive = path.join(temporary, 'CodexMulti.zip');
    await writeFile(archive, randomBytes(2048));
    const feed = path.join(temporary, 'appcast.xml');
    const args = [path.join(root, 'scripts/create-appcast.mjs'), app, archive, feed,
      'https://example.com/CodexMulti.zip', key, signer];
    assert.throws(() => execFileSync(process.execPath, args, { stdio: 'pipe' }), /verification_before_extraction_required/);
    execFileSync('/usr/bin/plutil', ['-replace', 'SUVerifyUpdateBeforeExtraction', '-bool', 'true', info]);
    execFileSync(process.execPath, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    const xml = await readFile(feed, 'utf8');
    const signature = Buffer.from(xml.match(/sparkle:edSignature="([^"]+)"/)[1], 'base64');
    assert.equal(verify(null, await readFile(archive), publicKey, signature), true);
    const changed = await readFile(archive); changed[0] ^= 1;
    assert.equal(verify(null, changed, publicKey, signature), false);
    await writeFile(feed, xml.replace('<title>CodexMulti</title>', '<title>Changed</title>'));
    assert.throws(() => execFileSync(signer, ['--ed-key-file', key, '--verify', feed], { stdio: 'pipe' }));
    await writeFile(key, randomBytes(32).toString('base64'), { mode: 0o600 });
    args[3] = path.join(temporary, 'mismatch.xml');
    assert.throws(() => execFileSync(process.execPath, args, { stdio: 'pipe' }), /signing_key_does_not_match_app/);
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
});

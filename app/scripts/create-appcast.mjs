import { createPublicKey, createPrivateKey, verify } from 'node:crypto';
import { lstat, readFile, writeFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';

const [app, archive, output, downloadURL, keyFile, signer] = process.argv.slice(2);
if (![app, archive, output, downloadURL, keyFile, signer].every(Boolean)) throw new Error('invalid_arguments');
if (new URL(downloadURL).protocol !== 'https:') throw new Error('https_required');
const keyInfo = await lstat(keyFile);
if (!keyInfo.isFile() || keyInfo.uid !== process.getuid() || (keyInfo.mode & 0o077) !== 0) throw new Error('unsafe_signing_key');
const seed = Buffer.from((await readFile(keyFile, 'utf8')).trim(), 'base64');
if (seed.length !== 32) throw new Error('sparkle_seed_format_required');
const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]), format: 'der', type: 'pkcs8' });
const publicKey = createPublicKey(privateKey);
const rawPublic = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
const info = path.join(app, 'Contents/Info.plist');
const value = (key) => execFileSync('/usr/bin/plutil', ['-extract', key, 'raw', '-o', '-', info], { encoding: 'utf8' }).trim();
if (rawPublic !== value('SUPublicEDKey')) throw new Error('signing_key_does_not_match_app');
if (value('SURequireSignedFeed') !== 'true') throw new Error('signed_feed_required');
if (value('SUVerifyUpdateBeforeExtraction') !== 'true') throw new Error('verification_before_extraction_required');
const manifest = JSON.parse(await readFile(path.join(app, 'Contents/Resources/runtime-manifest.json'), 'utf8'));
const signature = execFileSync(signer, ['--ed-key-file', keyFile, '-p', archive], { encoding: 'utf8' }).trim();
const bytes = await readFile(archive);
if (!verify(null, bytes, publicKey, Buffer.from(signature, 'base64'))) throw new Error('archive_signature_invalid');
const escape = (text) => String(text).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
const xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:codexmulti="https://codexmulti.dev/update/v1">
<channel><title>CodexMulti</title><item>
<title>CodexMulti ${escape(value('CFBundleShortVersionString'))}</title>
<sparkle:version>${escape(value('CFBundleVersion'))}</sparkle:version>
<sparkle:shortVersionString>${escape(value('CFBundleShortVersionString'))}</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
<codexmulti:runtimeID>${escape(manifest.runtime_id)}</codexmulti:runtimeID>
<codexmulti:updateProtocol>1</codexmulti:updateProtocol>
<enclosure url="${escape(downloadURL)}" sparkle:edSignature="${escape(signature)}" length="${bytes.length}" type="application/octet-stream"/>
</item></channel></rss>
`;
await writeFile(output, xml, { flag: 'wx', mode: 0o644 });
execFileSync(signer, ['--ed-key-file', keyFile, '--disable-signing-warning', output], { stdio: ['ignore', 'pipe', 'pipe'] });
execFileSync(signer, ['--ed-key-file', keyFile, '--verify', output], { stdio: ['ignore', 'pipe', 'pipe'] });
process.stdout.write('Appcast and archive signatures verified.\n');

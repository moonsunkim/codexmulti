import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const [app, mode = 'create'] = process.argv.slice(2);
if (!app || !['create', 'signed'].includes(mode)) throw new Error('invalid_arguments');
const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
const hashFile = async (file) => digest(await readFile(file));
const resources = path.join(app, 'Contents/Resources');
const proxy = path.join(resources, 'proxy');
const manifestPath = path.join(resources, 'runtime-manifest.json');
const files = [];
async function visit(relative) {
  const entry = path.join(proxy, relative);
  const info = await lstat(entry);
  if (info.isDirectory()) {
    for (const name of (await readdir(entry)).sort()) await visit(`${relative}/${name}`);
  } else {
    if (!info.isFile() || /[\t\r\n]/.test(relative)) throw new Error('unsafe_proxy_file');
    files.push({ relative, mode: (info.mode & 0o7777).toString(8), size: info.size, sha: await hashFile(entry) });
  }
}
for (const entry of ['bin', 'package.json', 'src']) await visit(entry);
files.sort((a, b) => a.relative < b.relative ? -1 : a.relative > b.relative ? 1 : 0);
const proxyTreeSHA256 = digest(files.map((file) => `${file.relative}\t${file.mode}\t${file.size}\t${file.sha}\n`).join(''));
const node = path.join(app, 'Contents/Helpers/node');
const launcher = path.join(app, 'Contents/Helpers/codexmulti-runtime-launcher');
const agent = path.join(app, 'Contents/Helpers/codexmulti-update-agent');
const previous = mode === 'signed' ? JSON.parse(await readFile(manifestPath, 'utf8')) : null;
if (previous && previous.proxy_tree_sha256 !== proxyTreeSHA256) throw new Error('proxy_changed_during_signing');
const manifest = {
  schema: 1,
  runtime_id: '',
  app_build: execFileSync('/usr/bin/plutil', ['-extract', 'CFBundleVersion', 'raw', '-o', '-', path.join(app, 'Contents/Info.plist')], { encoding: 'utf8' }).trim(),
  architecture: 'arm64',
  proxy_tree_sha256: proxyTreeSHA256,
  node_content_sha256: previous?.node_content_sha256 ?? await hashFile(node),
  node_signed_sha256: await hashFile(node),
  launcher_content_sha256: previous?.launcher_content_sha256 ?? await hashFile(launcher),
  launcher_signed_sha256: await hashFile(launcher),
  agent_content_sha256: previous?.agent_content_sha256 ?? await hashFile(agent),
  agent_signed_sha256: await hashFile(agent),
  activation_revision: 1,
  update_protocol: 1,
  config_schema: 1,
  state_schema: 1,
  minimum_gui_protocol: 1,
  maximum_gui_protocol: 1,
  proxy_files: Object.fromEntries(files.map((file) => [file.relative, file.sha])),
};
manifest.runtime_id = digest(`codexmulti-runtime-v1\n${manifest.architecture}\n${manifest.proxy_tree_sha256}\n${manifest.node_content_sha256}\n${manifest.launcher_content_sha256}\n${manifest.agent_content_sha256}\n${manifest.activation_revision}\n`);
if (previous && previous.runtime_id !== manifest.runtime_id) throw new Error('runtime_identity_changed_during_signing');
await writeFile(manifestPath, JSON.stringify(manifest, null, 2) + '\n', { mode: 0o644 });
process.stdout.write(manifest.runtime_id + '\n');

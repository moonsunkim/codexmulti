import { constants } from 'node:fs';
import { open } from 'node:fs/promises';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import path from 'node:path';

export function controlTokenPath(configPath) {
  return `${path.resolve(configPath)}.control-token`;
}

export async function readControlToken(file) {
  const handle = await open(file, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) !== 0 || stat.size !== 64) {
      throw new Error('control_token_not_private');
    }
    const token = await handle.readFile('utf8');
    if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('invalid_control_token');
    return token;
  } finally {
    await handle.close();
  }
}

export async function loadOrCreateControlToken(file) {
  if (!file) return randomBytes(32).toString('hex');
  try {
    return await readControlToken(file);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
  let handle;
  try {
    handle = await open(file, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
    await handle.writeFile(randomBytes(32).toString('hex'));
    await handle.sync();
  } catch (error) {
    if (error.code !== 'EEXIST') throw error;
  } finally {
    await handle?.close();
  }
  return await readControlToken(file);
}

export function authorizedControlRequest(request, token) {
  const actual = Buffer.from(String(request.headers.authorization ?? ''));
  const expected = Buffer.from(`Bearer ${token}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function localRequestError(request) {
  const hosts = request.rawHeaders.filter((_, index) => index % 2 === 0
    && request.rawHeaders[index].toLowerCase() === 'host');
  const port = request.socket.localPort;
  const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
  if (port === 80) {
    allowedHosts.add('127.0.0.1');
    allowedHosts.add('localhost');
  }
  if (hosts.length !== 1 || !allowedHosts.has(request.headers.host)) return 'invalid_local_host';
  // This is a CLI endpoint. Browsers must never borrow the pooled OAuth identity.
  if (request.headers.origin !== undefined
      || Object.keys(request.headers).some((name) => name.startsWith('sec-fetch-'))) {
    return 'browser_request_forbidden';
  }
  return null;
}

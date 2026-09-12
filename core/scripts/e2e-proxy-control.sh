#!/bin/sh
set -eu

CORE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$CORE_DIR/.." && pwd)
PROXY_REPO=${CODEXMULTI_PROXY_REPO:-$REPO_ROOT/proxy}
SCRATCH_ROOT=${CODEXMULTI_E2E_SCRATCH_ROOT:-${TMPDIR:-/private/tmp}/codexmulti-proxy-e2e}
ZIG=${CODEXMULTI_ZIG:-zig}
NODE_BIN=${CODEXMULTI_NODE:-$REPO_ROOT/app/.node/v26.8.1/bin/node}

test -f "$PROXY_REPO/src/server.mjs"
PROXY_REPO=$(CDPATH= cd -- "$PROXY_REPO" && pwd)
case "$PROXY_REPO" in
  "$REPO_ROOT"/*) ;;
  *) echo "proxy source must be inside the monorepo: $PROXY_REPO" >&2; exit 1 ;;
esac
test "$(git -C "$PROXY_REPO" rev-parse --show-toplevel)" = "$REPO_ROOT"
PROXY_RELATIVE=${PROXY_REPO#"$REPO_ROOT"/}
EXPECTED_PROXY_COMMIT=${CODEXMULTI_EXPECTED_PROXY_COMMIT:-$(git -C "$REPO_ROOT" log -1 --format=%H -- "$PROXY_RELATIVE")}
test "$(git -C "$REPO_ROOT" log -1 --format=%H -- "$PROXY_RELATIVE")" = "$EXPECTED_PROXY_COMMIT"
mkdir -p "$SCRATCH_ROOT"
chmod 700 "$SCRATCH_ROOT"
SCRATCH_ROOT=$(CDPATH= cd -- "$SCRATCH_ROOT" && pwd -P)
RUN_DIR=$(mktemp -d "$SCRATCH_ROOT/proxy-e2e.XXXXXX")
SERVER_PID=

cleanup() {
  if test -n "$SERVER_PID" && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  case "$RUN_DIR" in
    "$SCRATCH_ROOT"/proxy-e2e.*) rm -rf -- "$RUN_DIR" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

PORT=$("$NODE_BIN" --input-type=module -e '
  import net from "node:net";
  const server = net.createServer();
  server.listen(0, "127.0.0.1", () => {
    process.stdout.write(String(server.address().port));
    server.close();
  });
')
BASE_URL="http://127.0.0.1:$PORT"
CONFIG_PATH="$RUN_DIR/config.json"
APP_SUPPORT="$RUN_DIR/home/Library/Application Support"
APP_DATA_DIRECTORY=$(sed -n 's/^pub const app_data_directory_name = "\([^"]*\)";/\1/p' "$CORE_DIR/src/runtime_paths.zig")
test -n "$APP_DATA_DIRECTORY"
APP_ROOT="$APP_SUPPORT/$APP_DATA_DIRECTORY"

RUN_DIR="$RUN_DIR" APP_ROOT="$APP_ROOT" CONFIG_PATH="$CONFIG_PATH" PORT="$PORT" "$NODE_BIN" --input-type=module <<'NODE'
import path from 'node:path';
import { chmod, mkdir, writeFile } from 'node:fs/promises';

const future = 4_102_444_800;
const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = (claims) => `${encode({ alg: 'none', typ: 'JWT' })}.${encode(claims)}.fixture`;
const accounts = [];
for (const suffix of ['a', 'b', 'c']) {
  const directory = path.join(process.env.APP_ROOT, 'accounts', `fixture-${suffix}`, 'codex');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  await chmod(directory, 0o700);
  const authFile = path.join(directory, 'auth.json');
  const auth = {
    auth_mode: 'chatgpt',
    OPENAI_API_KEY: null,
    tokens: {
      id_token: jwt({ fixture: suffix }),
      access_token: jwt({ fixture: suffix, exp: future }),
      refresh_token: `fixture-refresh-${suffix}`,
      account_id: `fixture-account-${suffix}`,
    },
    last_refresh: new Date(0).toISOString(),
  };
  await writeFile(authFile, `${JSON.stringify(auth)}\n`, { mode: 0o600 });
  await chmod(authFile, 0o600);
  accounts.push({ name: `route-${suffix}`, label: `Fixture ${suffix.toUpperCase()}`, auth_file: authFile });
}
const config = {
  listen_host: '127.0.0.1',
  port: Number(process.env.PORT),
  mode: 'failover',
  accounts,
  upstream_chatgpt_base_url: 'http://127.0.0.1:9/backend-api/',
  upstream_openai_base_url: 'http://127.0.0.1:9/backend-api/codex',
  request_body_limit_bytes: 65_536,
  token_refresh_skew_seconds: 300,
  default_cooldown_seconds: 1800,
  cooldown_safety_margin_seconds: 60,
  allow_insecure_upstream: true,
  state_file: path.join(process.env.RUN_DIR, 'state', 'state.json'),
  log_file: null,
};
await writeFile(process.env.CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
await chmod(process.env.CONFIG_PATH, 0o600);
NODE

"$ZIG" build-exe -O ReleaseSafe "$CORE_DIR/src/proxy_e2e_client.zig" -femit-bin="$RUN_DIR/proxy-e2e-client"
"$NODE_BIN" "$PROXY_REPO/src/server.mjs" --config "$CONFIG_PATH" >"$RUN_DIR/server.log" 2>&1 &
SERVER_PID=$!

READY=false
attempt=0
while test "$attempt" -lt 100; do
  if test -f "$CONFIG_PATH.control-token"; then
    (umask 077; { printf 'Authorization: Bearer '; cat "$CONFIG_PATH.control-token"; printf '\n'; } > "$CONFIG_PATH.control-header")
  fi
  if curl --header "@$CONFIG_PATH.control-header" --noproxy '*' --silent --fail "$BASE_URL/_proxy/status" >/dev/null 2>&1; then
    READY=true
    break
  fi
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.05
done
if test "$READY" != true; then
  echo 'E2E proxy startup: FAIL'
  exit 1
fi

"$RUN_DIR/proxy-e2e-client" initial "$BASE_URL" "$CONFIG_PATH" "$APP_SUPPORT"

RUN_DIR="$RUN_DIR" APP_ROOT="$APP_ROOT" CONFIG_PATH="$CONFIG_PATH" "$NODE_BIN" --input-type=module <<'NODE'
import path from 'node:path';
import { chmod, mkdir, readFile, writeFile } from 'node:fs/promises';

const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
const jwt = (claims) => `${encode({ alg: 'none', typ: 'JWT' })}.${encode(claims)}.fixture`;
const directory = path.join(process.env.APP_ROOT, 'accounts', 'fixture-d', 'codex');
await mkdir(directory, { recursive: true, mode: 0o700 });
await chmod(directory, 0o700);
const authFile = path.join(directory, 'auth.json');
await writeFile(authFile, `${JSON.stringify({
  auth_mode: 'chatgpt',
  OPENAI_API_KEY: null,
  tokens: {
    id_token: jwt({ fixture: 'd' }),
    access_token: jwt({ fixture: 'd', exp: 4_102_444_800 }),
    refresh_token: 'fixture-refresh-d',
    account_id: 'fixture-account-d',
  },
  last_refresh: new Date(0).toISOString(),
})}\n`, { mode: 0o600 });
await chmod(authFile, 0o600);

const config = JSON.parse(await readFile(process.env.CONFIG_PATH, 'utf8'));
const [a, b, c] = config.accounts;
config.accounts = [
  c,
  { ...a, name: 'route-a-next' },
  { name: 'route-d', label: 'Fixture D', auth_file: authFile },
  b,
];
await writeFile(process.env.CONFIG_PATH, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
await chmod(process.env.CONFIG_PATH, 0o600);
NODE

"$RUN_DIR/proxy-e2e-client" reload "$BASE_URL" "$CONFIG_PATH" "$APP_SUPPORT"
echo 'E2E synthetic proxy control: PASS'

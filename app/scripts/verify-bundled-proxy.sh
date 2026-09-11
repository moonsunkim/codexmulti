#!/bin/bash

set -euo pipefail

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/verify-bundled-proxy.sh <CodexMulti.app>\n' >&2
}

test "$#" -eq 1 || { usage; exit 2; }
app="$1"
node="$app/Contents/Helpers/node"
server="$app/Contents/Resources/proxy/src/server.mjs"
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
LSOF_BIN="${LSOF_BIN:-/usr/sbin/lsof}"

test -d "$app" || die "candidate app does not exist: $app"
test -x "$node" || die "bundled Node runtime is missing or not executable: $node"
test ! -L "$node" || die "bundled Node runtime must not be a symlink"
test -f "$server" || die "bundled proxy server is missing: $server"
test -x "$CURL_BIN" || die "curl is unavailable: $CURL_BIN"
test -x "$LSOF_BIN" || die "lsof is unavailable: $LSOF_BIN"

temp_home="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-proxy-headless.XXXXXX")"
temp_root="$temp_home"
config_path="$temp_root/config.json"
stdout_path="$temp_root/proxy.stdout"
stderr_path="$temp_root/proxy.stderr"
status_path="$temp_root/status.json"
mkdir -p "$temp_root/tmp"
proxy_pid=""

cleanup() {
    local attempt
    if test -n "$proxy_pid" && kill -0 "$proxy_pid" 2>/dev/null; then
        kill -TERM "$proxy_pid" 2>/dev/null || true
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$proxy_pid" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$proxy_pid" 2>/dev/null; then
            kill -KILL "$proxy_pid" 2>/dev/null || true
        fi
        wait "$proxy_pid" 2>/dev/null || true
    fi
    case "$temp_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-proxy-headless.*) /bin/rm -rf -- "$temp_root" ;;
    esac
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM





port=""
for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    port="$(HOME="$temp_home" TMPDIR="$temp_root/tmp" "$node" -e '
        const { randomInt } = require("node:crypto");
        process.stdout.write(String(randomInt(49152, 65536)));
    ')"
    if test "$port" != "8787" && ! "$LSOF_BIN" -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | grep -q .; then
        break
    fi
    port=""
done
printf '%s\n' "$port" | grep -Eq '^[0-9]+$' || die "could not allocate a random loopback port"
test "$port" != "8787" || die "refusing to use the owner's conventional proxy port 8787"





printf '{\n  "auth_mode": "chatgpt",\n  "tokens": {\n    "access_token": "headless-verification-not-a-token",\n    "refresh_token": "headless-verification-not-a-token",\n    "account_id": "headless-verification"\n  }\n}\n' > "$temp_home/auth.json"
chmod 600 "$temp_home/auth.json"
printf '{\n  "listen_host": "127.0.0.1",\n  "port": %s,\n  "mode": "failover",\n  "accounts": [{ "name": "headless-1", "label": "headless verification", "auth_file": "%s/auth.json" }],\n  "state_file": "%s/state.json",\n  "log_file": null\n}\n' \
    "$port" "$temp_home" "$temp_home" > "$config_path"

HOME="$temp_home" TMPDIR="$temp_root/tmp" \
    "$node" "$server" --config "$config_path" > "$stdout_path" 2> "$stderr_path" &
proxy_pid=$!

http_code=""
for _attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50; do
    http_code="$("$CURL_BIN" --silent --show-error --max-time 0.5 \
        --output "$status_path" --write-out '%{http_code}' \
        "http://127.0.0.1:$port/_proxy/status" 2>/dev/null || true)"
    test "$http_code" = "200" && break
    kill -0 "$proxy_pid" 2>/dev/null || break
    sleep 0.1
done

if test "$http_code" != "200"; then
    printf 'error: bundled proxy did not return HTTP 200 on isolated port %s\n' "$port" >&2
    if test -s "$stdout_path"; then
        printf '%s\n' '--- proxy stdout ---' >&2
        sed -n '1,40p' "$stdout_path" >&2
    fi
    if test -s "$stderr_path"; then
        printf '%s\n' '--- proxy stderr ---' >&2
        sed -n '1,40p' "$stderr_path" >&2
    fi
    exit 1
fi

printf 'Bundled proxy headless verification: PASS\n'
printf '  endpoint: http://127.0.0.1:%s/_proxy/status\n' "$port"
printf '  HOME: isolated temporary directory\n'
printf '  status JSON:\n'
sed 's/^/    /' "$status_path"

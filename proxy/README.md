# codexmulti-proxy

`codexmulti-proxy` is a local failover proxy that sits in front of multiple Codex ChatGPT OAuth accounts. It runs as a per-user service and listens only on loopback. The proxy keeps an ordered pool of account-specific `auth.json` files, substitutes the account's identity headers, and switches only after a confirmed `usage_limit_reached`: an HTTP `429` before streaming, a rejected WebSocket handshake, or a Responses WebSocket error before any response event reaches the client.

WebSocket Upgrades to upstream routes use the active account's identity headers. Responses WebSockets select an account for each `response.create`, honor manual switches on existing client connections, and retry a definitive usage-limit error before any response event is delivered. Other WebSocket routes remain opaque byte tunnels. The `/_proxy` control API continues to reject Upgrades with `426 Upgrade Required`. The local control API is version 2. This project is not a general forward proxy, TLS MITM, account creator, or `codex cloud` proxy.

## Requirements

- macOS with Codex CLI 0.146.0 or newer
- Node.js 22.15 or later (the proxy uses the standard-library zstd decoder)
- No npm dependencies
- CodexMulti account store, with one complete `CODEX_HOME` per ChatGPT account

The proxy never reads or writes the main `~/.codex/auth.json`: startup rejects that path. It also rejects duplicate account auth paths and any state/log path that collides with an auth file.

## CodexMulti integration

CodexMulti bundles this proxy and starts and manages it automatically. CodexMulti app users normally do not need to run `serve` or install a separate background service. The standalone commands and launchd template in this repository remain available for development, inspection, and independent operation.

## Import CodexMulti credentials in place

The proxy reuses CodexMulti's account-specific `auth.json` files at their existing paths. It never copies, moves, or symlinks credentials, because copying a rotating refresh-token chain can invalidate one of the writers.

Preview the eligible `provider=codex`, enabled, connected accounts without writing a config:

```sh
./bin/codexmulti-proxy import-codexmulti --dry-run \
  --out "$HOME/.config/codexmulti/proxy.json"
```

The table contains only generated names, CodexMulti labels, access-token expiration times, and validation results. After checking it, create or update the config:

```sh
./bin/codexmulti-proxy import-codexmulti \
  --out "$HOME/.config/codexmulti/proxy.json"
```

Use `--store DIR` only when CodexMulti is stored somewhere other than its standard Application Support directory. The import keeps source order, names accounts `codex-1` through `codex-N`, points `auth_file` directly into each CodexMulti `CODEX_HOME`, and replaces only `accounts` when the output config already exists. It writes nothing if any selected credential fails validation.

Each account `codex` directory must be mode `0700`, and each `auth.json` must be mode `0600`. Symlinked credentials, traversal components, malformed auth data, and group/world-accessible credential directories or files are rejected. A duplicate account identity in different files produces a names-only warning but does not stop startup.

`config.example.json` shows the resulting shape without real storage keys or labels. Production startup accepts exactly these upstream bases:

```text
https://chatgpt.com/backend-api/
https://chatgpt.com/backend-api/codex
```

`allow_insecure_upstream` defaults to `false`. It may be set to `true` only for tests, and then only `http://127.0.0.1:<port>` upstreams are accepted. Never enable it for normal operation.

## Run and inspect

Run in the foreground first:

```sh
./bin/codexmulti-proxy --config "$HOME/.config/codexmulti/proxy.json" serve
./bin/codexmulti-proxy --config "$HOME/.config/codexmulti/proxy.json" status
```

The control commands are:

```sh
./bin/codexmulti-proxy --config CONFIG switch codex-3
./bin/codexmulti-proxy --config CONFIG pause codex-3
./bin/codexmulti-proxy --config CONFIG pause codex-3 --wait
./bin/codexmulti-proxy --config CONFIG pause codex-3 --wait 60
./bin/codexmulti-proxy --config CONFIG reload codex-3
./bin/codexmulti-proxy --config CONFIG clear-cooldown codex-3
./bin/codexmulti-proxy --config CONFIG refresh codex-3
./bin/codexmulti-proxy --config CONFIG login codex-3
./bin/codexmulti-proxy --config CONFIG status --labels
```

The primary operational commands are:

- `import-codexmulti`: discovers eligible CodexMulti OAuth accounts and writes their existing credential paths into the proxy config; `--dry-run` validates without writing.
- `status`: reports proxy and account state without exposing labels or credential paths by default; add `--labels` to include labels.
- `refresh <name>`: forces an in-place OAuth refresh for one account and reports only success or failure and the new access-token expiry.
- `clear-cooldown <name>`: removes a stale usage-limit cooldown without rereading or changing credentials.

## Control API v2

Control API v2 is available only from loopback under `/_proxy`. The API version describes this control contract; it is not an additional URL prefix.

| Method | Endpoint | Purpose |
| --- | --- | --- |
| `GET` | `/_proxy/status` | Return proxy and per-account state. |
| `POST` | `/_proxy/switch` | Move the selection cursor to the account named in the JSON body. |
| `POST` | `/_proxy/reload-config` | Validate and atomically reload account configuration from the startup config path. |
| `POST` | `/_proxy/accounts/:name/pause` | Stop assigning new requests to an account. |
| `POST` | `/_proxy/accounts/:name/reload` | Reread and validate an account's credential file. |
| `POST` | `/_proxy/accounts/:name/refresh` | Force an in-place OAuth refresh for an account. |
| `POST` | `/_proxy/accounts/:name/clear-cooldown` | Clear an eligible stale cooldown. |

`reload-config` and `clear-cooldown` require an empty JSON object. The CLI commands above are the preferred interface for routine local operation.

The v2 status API includes the startup `config_path` plus each account's optional `label` and normalized absolute `auth_file`. It never includes credential tokens, provider account IDs, or request headers. CLI `status` removes `label` and `auth_file` by default; `status --labels` restores only `label`. `refresh` forces one in-place OAuth refresh under the account mutex and prints only `ok`/`failed` and the new access expiry. After initial import, run it for every account to probe the existing refresh chains. Use `login` only for a chain that fails the probe.

In v2 status, top-level `in_flight` counts admitted HTTP requests and client WebSocket connections; each account's `in_flight` counts its upstream requests and WebSocket peers. A client WebSocket can have no upstream peer while idle, or retain peers on several accounts after switching. These counts are independent: clients must not require the account counts to sum to the top-level count.

`pause` persists `PAUSED`, blocks new selections, and immediately returns `202` with the account's current `in_flight` count; it never interrupts an existing stream. `pause --wait` preserves the draining CLI workflow by polling v2 status until that count reaches zero. With no seconds argument it waits for up to 60 seconds. `login` always performs the same pause → status drain → foreground `codex login` → reload sequence when the proxy is reachable. A failed or timed-out login leaves the account paused. `reload` validates the on-disk file and clears pause/cooldown only on success.

`clear-cooldown <name>` drops a stale cooldown when the account's limit was reset outside the proxy, for example by redeeming a reset credit on chatgpt.com. Without it the proxy keeps honoring the `resets_at` the server returned with the original 429, which can be days away. It maps to:

```sh
curl --fail-with-body -X POST \
  -H 'Content-Type: application/json' \
  --data '{}' \
  http://127.0.0.1:8787/_proxy/accounts/codex-3/clear-cooldown
```

The body must be exactly an empty JSON object. The call clears only `cooldown_until` and a `usage_limit_reached` reason under the failover mutex, persists state atomically, and returns `200` with just `{"name","state","cooldown_until"}`. An unknown name is `404 unknown_account`. A `PAUSED` account is `409 account_paused` and an `INVALID` one is `409 account_invalid`: neither has a cooldown to lift, and both keep their existing `reload`/`login` recovery path. Unlike `reload`, it never rereads or revalidates the credential file.

To apply an importer-written account add, removal, rename, label change, or reorder without restarting the daemon, send exactly an empty JSON object:

```sh
curl --fail-with-body -X POST \
  -H 'Content-Type: application/json' \
  --data '{}' \
  http://127.0.0.1:8787/_proxy/reload-config
```

The daemon rereads only the config path fixed at startup. Any non-account setting change returns `409 restart_required`; an active upstream request returns `409 proxy_busy`. Candidate config and credentials are fully validated before commit. The commit gate returns `503 proxy_reconfiguring` to new upstream admission, atomically saves migrated state, and swaps the full account generation. Pause, cooldown, invalid state, and cursor ownership follow exact normalized `auth_file` matches; new files start `READY`, removed files disappear, and a removed cursor falls back to the new first account.

To route Codex through the proxy, preserve the rest of `~/.codex/config.toml` and add only these top-level keys:

```toml
chatgpt_base_url = "http://127.0.0.1:8787/backend-api/"
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

Codex WebSocket handshakes are relayed to the configured upstream. If the upstream rejects a handshake, that status and body are returned unchanged and Codex may choose its HTTP/SSE fallback.

When a tool or script runs `codex exec` without a terminal on stdin, append `</dev/null`; otherwise Codex can wait indefinitely at `Reading additional input from stdin`.

`bin/codex-direct` bypasses the proxy without editing that file:

```sh
./bin/codex-direct exec "reply with ok"
```

## Standalone launchd operation

Do not load the template as-is. Copy `launchd/dev.codexmulti.app.proxy.plist.template`, replace `/ABSOLUTE/INSTALL`, `/Users/USER`, and the Node path with pinned absolute paths, then place the rendered file at `~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist`.

Before loading it, confirm foreground `serve`, `status`, and local HTTP/SSE and WebSocket smoke tests. The service validates config, state, and every auth file before binding. A corrupt state file fails startup rather than silently bypassing cooldown. `RunAtLoad`, `KeepAlive`, and persisted atomic state restore the cursor, pauses, invalid markers, and cooldown deadlines after a restart.

Typical user-agent commands, run only after reviewing the rendered plist, are:

```sh
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.codexmulti.app.proxy.plist"
launchctl kickstart -k "gui/$(id -u)/dev.codexmulti.app.proxy"
launchctl print "gui/$(id -u)/dev.codexmulti.app.proxy"
```

The standalone repository does not install or load the agent automatically. The CodexMulti app's bundled distribution manages proxy startup itself.

## Failover behavior

- The cursor's first `READY` account stays active until it is paused, invalid, or receives a confirmed usage limit.
- `error.resets_at` wins over the active rate-limit header family's reached primary/secondary `reset-at`; otherwise the default is 30 minutes. The configured safety margin is added in every case.
- A request tries each `READY` account at most once. A 401 is the only same-account retry: reload a changed disk token, otherwise refresh once, then retry that account once.
- DNS, connect/TLS errors, 5xx, interrupted streams, plan mismatch, `usage_not_included`, and unrecognized 429 responses are terminal. They never cause an account switch.
- A WebSocket handshake may try each eligible account at most once after a complete `429 usage_limit_reached` response. Responses WebSockets also retry an in-band `error` with `error.type=usage_limit_reached` before any response event has been delivered. A response that has emitted an event, or received cancellation or other mid-response input, is not replayed.
- Each Responses `response.create` selects the current ready account. Existing responses finish on their original upstream connection. Named streams keep independent routing and same-stream requests remain FIFO.
- Moving an incremental request to another account expands its `previous_response_id` into the retained input and completed output, then clears the upstream-only reference. Continuation state stays in memory, bounded by the configured body limit and 128 response entries per client connection. If complete context is unavailable, the standard `previous_response_not_found` error asks the client to resend full context; context is never silently truncated. These semantics follow the [Responses WebSocket recovery guidance](https://developers.openai.com/api/docs/guides/websocket-mode#reconnect-and-recover).
- Responses WebSocket compression is not negotiated so usage errors and request boundaries remain inspectable. Fragments, ping/pong, large inputs, and upstream backpressure are handled without logging payloads. Non-Responses WebSocket routes retain their original opaque transport.
- A downstream client closing a stream is an informational `client_closed`, not a proxy error; a genuine upstream interruption remains `upstream_stream_error` and is not retried.
- When every usable account is cooling down, the earliest deadline receives exactly one probe. There is no cached limit response and no 401 retry in this mode.
- Only a 2xx probe on the Responses route (`/backend-api/codex/responses`) clears that account's cooldown. A 2xx on any other route, such as `/backend-api/wham/usage` or `/backend-api/ps/plugins/**`, is relayed unchanged with the cooldown left in place: those routes answer 200 while the model quota is still exhausted, so treating them as recovery would flip the account between `READY` and `COOLDOWN`.
- Request bodies are buffered as raw bytes up to 64 MiB. Compressed request bytes are never decoded. Successful responses stream with backpressure and no proxy idle timeout. Connecting and waiting for response headers have separate bounded timeouts; client cancellation releases the upstream connection and account lease even before headers arrive.

## Shared credential writer behavior

CodexMulti and the proxy may both refresh the same in-place credential. The default refresh skew is 48 hours (`172800` seconds), so the proxy normally refreshes well before Codex's five-minute window. Before every upstream attempt, it compares the auth file's modification time, size, and inode with the last loaded snapshot and reloads a changed file under the account mutex.

Production refresh always sends a JSON `POST` to `https://auth.openai.com/oauth/token` with the Codex client ID embedded in the implementation; `auth.json` supplies the refresh token, not an endpoint or client configuration. If a refresh request fails and a reread finds that another writer rotated the refresh token, the proxy accepts that writer's still-valid access token and does not retry the stale chain. Successful writes remain atomic temp-file replacements.

Transient transport, timeout, 429 and server failures during proactive refresh retain a still-valid access token and schedule a retry. Definitive authentication rejection or expiration invalidates the account. Successful renewal clears the warning.

There is no interprocess writer lock. A rare case in which CodexMulti and the proxy both refresh successfully at the same time remains last-writer-wins; the stat/reload and failed-stale-chain recovery cover the expected shared-writer cases, not that race completely.

## State, logs, and security

Default runtime files are:

```text
~/.config/codexmulti/proxy.json
~/Library/Application Support/CodexMulti/proxy-state.json
~/Library/Logs/CodexMulti/proxy.log
```

State contains account names, each normalized `auth_file`, cursor, pause/cooldown reason, and timestamps—never tokens or account IDs. A legacy state file without `auth_file` is loaded once by name and atomically rewritten in the new form. Logs are mode `0600`, rotate at a bounded size, and allow only bounded request, account, cooldown, streaming-termination, and `ws_open`/`ws_close`/`ws_failover` diagnostics. WebSocket close events contain only duration and directional byte counts besides event metadata; failover events contain the selected account name and attempt count. A successful config reload adds one `config_reloaded` info event containing only added/removed/renamed/migrated counts. Error messages are secret-redacted and limited to 200 characters. Labels, paths, authorization, cookies, token/account IDs, attestation values, bodies, tail buffers, and query strings are never logged.

The service binds only `127.0.0.1`. HTTP and WebSocket entry points require an exact loopback Host and reject browser Origin and Fetch Metadata headers. The control API additionally requires a random bearer capability stored beside the config as `<config-path>.control-token`, owned by the current UID and mode `0600`; the app and CLI read it automatically. Keep this file private. Direct `curl` control calls must read it into an Authorization header without putting the value in shell history or process arguments.

Ordinary proxy traffic retains machine-local trust for compatibility with Codex: another user or process on the same Mac can send non-browser requests through the pool. TCP loopback does not enforce a same-user boundary for that traffic. Use only on a Mac whose local users and processes you trust.

## Test

```sh
npm test
```

Tests use `node:test`, port `0`, synthetic JWT-shaped tokens, a synthetic CodexMulti store, fake HTTP/SSE/WebSocket upstreams, and a fake refresh service. The Codex binary smoke uses only an isolated temporary `CODEX_HOME` and loopback base overrides. It must never be pointed at real ChatGPT or OAuth endpoints.

## Rollback

For immediate bypass, run the same command through `bin/codex-direct`. For permanent rollback:

1. `launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/dev.codexmulti.app.proxy.plist"`
2. Remove only the two proxy base keys from `~/.codex/config.toml`; preserve every other setting.
3. Run one short direct Codex turn and verify it completes.

Do not delete, copy, or otherwise modify CodexMulti account directories during rollback. Do not automatically delete proxy state or logs either. The main Codex auth file is outside this proxy's authority and must remain untouched.

## Version boundary

Transport coverage includes HTTP/SSE failover, Responses WebSocket frame handling, continued
conversations, manual switching, independent streams and opaque pass-through for other WebSocket
routes. An upstream-426 → POST/SSE fallback smoke runs against a compatible installed Codex CLI;
if the CLI is unavailable, that smoke is skipped with its reason. Selection uses the ordered sticky
cursor, not round-robin. See [Failover behavior](#failover-behavior) for retry and context-cache limits.

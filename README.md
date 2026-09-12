# CodexMulti

**English** · [한국어](README.ko.md) · [日本語](README.ja.md)

<p align="center">
  <img src="assets/hero.png" width="100%" alt="CodexMulti — one Mac, many Codex accounts, with automatic failover">
</p>

**When one Codex account hits its limit, keep going with the next.**

CodexMulti puts your Codex accounts in one macOS menu-bar app. See what each account has left,
choose their order, and let automatic failover handle confirmed usage-limit errors.

[Download](https://github.com/moonsunkim/codexmulti/releases/latest) · [Changelog](CHANGELOG.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

[![CI](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml/badge.svg)](https://github.com/moonsunkim/codexmulti/actions/workflows/ci.yml)


- **See your whole pool.** Remaining usage, reset times and account availability are together in one window. The menu bar keeps the pool total close by; **Accounts…** opens the full list in one click.
- **Set the order once.** Drag accounts into your preferred order. When an eligible request hits a confirmed usage limit, the proxy tries the next available account.
- **Turn on one switch.** Failover setup includes the local proxy and its Node runtime. Added or reconnected accounts are picked up automatically while the app is open.
- **Keep credentials local.** Each account has its own Codex directory and Keychain backup. There is no CodexMulti account to create or hosted service to connect to.

## What is Failover, and why use it?

A coding task can stop when one Codex account reaches its usage limit, even if another account
still has capacity. Without automatic switching, you have to choose another account and retry
the request yourself.

**Failover automatically tries the next available account when the current one returns a confirmed
usage-limit error.** Add your accounts, put them in your preferred order, and turn on **Use Failover**.
CodexMulti routes eligible Codex requests through a local proxy on your Mac.

For example, if account A reaches its limit before a response starts, the proxy retries that request
with account B. If B is also at its limit, it tries the next eligible account. You can keep working
without manually changing the account for each limit error.

The accounts keep their own subscriptions and limits; Failover makes their available capacity
easier to use. It does not replay a response that has already started or retry every kind of error.
See [when account switching happens](#when-will-it-switch-accounts) for the exact conditions.

## Install

You need **an Apple Silicon Mac running macOS 26 or later**, Codex CLI with ChatGPT sign-in,
and at least two accounts for failover to be useful.

```sh
brew install --cask moonsunkim/tap/codexmulti
```

Or use the [latest release](https://github.com/moonsunkim/codexmulti/releases/latest).
Releases from 0.2.1 onward are Developer ID signed and notarized by Apple.

<details>
<summary>Script installer or manual installation</summary>

```sh
curl -fsSL https://raw.githubusercontent.com/moonsunkim/codexmulti/main/install.sh | bash
```

The installer checks the release's published SHA-256, preserves an existing app as
`CodexMulti.app.previous`, installs to `/Applications`, and opens the app in the background.
It preserves Gatekeeper quarantine attributes.

For manual installation, download `CodexMulti-<version>.zip` and the matching `.sha256` file.
Put both in one directory, then verify the archive before expanding it:

```sh
shasum -a 256 -c CodexMulti-<version>.zip.sha256
```

Move the verified `CodexMulti.app` into `/Applications` and open it.

</details>

## Two steps to get going

1. **Add your accounts.** Click **+**, give the account a name, and complete the official browser sign-in. Repeat for the accounts you want in the pool.
2. **Turn on Use Failover.** Open **Settings**. The app prepares its bundled proxy, checks that it is working, and connects Codex to it.

Use Codex as usual. If an account returns a confirmed usage-limit error before a response starts,
the same request can continue through the next eligible account. Paused, invalid and cooling
accounts are skipped.

Account additions, reconnections and order changes are applied automatically while the app is open.
Changes that need a proxy reload wait for active requests to finish. Closing the menu-bar app leaves
a healthy proxy running; turning Failover off restores direct Codex connections after active requests finish.

Open **Accounts…** from the menu bar to see your full pool.
In an account's **…** menu, **Use in failover…** selects that account for new requests.
**Pause in failover** excludes it from receiving new requests; **Resume in failover** includes it again.
Requests already in flight continue on their current account.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-light.png">
  <img alt="CodexMulti account pool with remaining usage, reset times and active, ready, cooling and paused states" src="assets/screenshots/accounts-light.png">
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/settings-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/settings-light.png">
  <img alt="Current settings with one Failover switch and a wide language selector aligned to the right" src="assets/screenshots/settings-light.png">
</picture>

Choose your usage refresh interval, preferred usage window and theme. The language menu supports
**System, English, 한국어 and 日本語**.

<details>
<summary>Take a closer look at an account</summary>

Expand an account to see its usage windows, authentication and failover status, last refresh,
and reported reset credits.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/screenshots/accounts-expanded-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="assets/screenshots/accounts-expanded-light.png">
  <img alt="Expanded account details showing usage, token status, refresh time and available reset credits" src="assets/screenshots/accounts-expanded-light.png">
</picture>

All screenshots use synthetic accounts.

</details>

## When will it switch accounts?

Only after a confirmed usage-limit response: a pre-stream HTTP `429` with error type
`usage_limit_reached`, or that same response during a WebSocket handshake. Each eligible account
is tried at most once for the request.

Network failures, `5xx`, interrupted streams, plan mismatches, `usage_not_included` and unrecognized
`429` responses stop the request. A response that has already started is not replayed on another account.
If no eligible account remains, the request fails rather than retrying indefinitely.

The app does not increase an account's limits or change its subscription. Proxy compatibility tracks
the Codex CLI; see the [release notes](https://github.com/moonsunkim/codexmulti/releases/latest) before upgrading.

## Your accounts stay on your Mac

There is no telemetry, analytics or CodexMulti-hosted control plane. Authentication, usage checks and
inference contact provider services directly. The proxy listens on loopback and its control API uses
a private per-user capability.

Each account uses an isolated Codex home. Credentials remain local, with a Keychain backup; your
personal `~/.codex/auth.json` is not replaced. Enabling Failover edits only the two managed base-URL
entries in `~/.codex/config.toml` and leaves a timestamped backup. Turning it off restores direct routing.

See [Security](SECURITY.md) and [proxy security](proxy/README.md#state-logs-and-security) for the trust
boundary and log-handling details.

## Build from source

You need Zig 0.16.0 on `PATH`, Xcode (or the Command Line Tools) with Swift 6 and the macOS 26 SDK,
and macOS 26 on Apple Silicon.

```sh
./app/scripts/fetch-node.sh                                        # pinned Node, SHA-256 verified
./app/scripts/build-app.sh                                         # → app/dist/staging/CodexMulti.app
./app/scripts/screenshots.sh
./app/scripts/verify-provenance.sh app/dist/staging/CodexMulti.app
./app/scripts/verify-bundled-proxy.sh app/dist/staging/CodexMulti.app
```

The build compiles the core as an `aarch64-macos` object, links it into the Swift executable, and
assembles the bundle with the pinned Node binary and the proxy source. Provenance markers record the
core source digest, the bridge schema, the proxy commit, a digest of the bundled proxy tree, and the
Node hashes; `verify-provenance.sh` recomputes them rather than trusting the text.

Tests:

```sh
(cd core && zig build test && zig build test-bridge)
(cd app && CODEXMULTI_TEST_HEADLESS=1 swift test)   # never plain `swift test`: it opens windows
(cd proxy && npm test)
```

CI checks the Zig core, Node proxy, SwiftUI shell and distribution scripts on macOS.
The SwiftUI shell job runs with the macOS 26 SDK.

Signing and release packaging are separate from the ordinary build: `app/scripts/package-signed-macos.sh`
audits the local signing identity, signs the bundled Node and then the app inside-out, and refuses a
bundle whose provenance or designated requirement does not match.

## How it is built

| Part | Responsibility |
| --- | --- |
| [SwiftUI app](app/) | Windows, menus, accessibility and macOS integration. |
| [Zig core](core/) | Accounts, background work, guarded routing changes, and all UI text. |
| [Node proxy](proxy/) | Local request forwarding and failover across eligible accounts. |

The app sends typed intents to the core and renders its returned state. The proxy runs independently
as a per-user LaunchAgent, so requests can continue after the menu-bar app closes. Both the proxy and
its pinned Node runtime are bundled in the app.

<details>
<summary>Recovery, removal and manual routing repair</summary>

The app retries recovery while Failover is enabled. If a change must wait for active requests,
its status explains the wait. Turn Failover off to restore direct Codex routing after those requests finish.

Before removing the app, quit Codex clients and run:

```sh
"/Applications/CodexMulti.app/Contents/Helpers/codexmulti-maintenance" prepare-uninstall
brew uninstall --cask codexmulti
```

The bundled helper restores only CodexMulti's two managed routing entries, drains healthy requests, checks the LaunchAgent's exact program arguments, and removes its plist and service receipt. Account credentials, usage history and reset records remain available for reinstall. Homebrew runs this helper automatically on removal; if it reports a conflict or a busy service, resolve that condition and retry before deleting the app. Homebrew upgrades and reinstalls also run the cleanup: reopen CodexMulti and turn the proxy on again afterward. `--zap` additionally removes the app's saved account data.

If the app or helper cannot run, open `~/.codex/config.toml` in a text editor. Remove only these exact root-level entries when present, preserving all other settings:

```toml
chatgpt_base_url = "http://127.0.0.1:8787/backend-api/"
openai_base_url = "http://127.0.0.1:8787/backend-api/codex"
```

Then inspect `launchctl print "gui/$(id -u)/dev.codexmulti.app.proxy"`. Only if its program arguments point to your CodexMulti app's `Contents/Helpers/node`, `Contents/Resources/proxy/src/server.mjs`, `--config`, and your proxy config, stop it with `launchctl bootout "gui/$(id -u)/dev.codexmulti.app.proxy"` and remove `~/Library/LaunchAgents/dev.codexmulti.app.proxy.plist`. Restart Codex clients so they reread the direct-connection configuration. Do not replace the whole shared config with an old backup.

Proxy control requires a private per-user capability. Ordinary Codex proxy traffic is trusted at the local-machine level, so use it only on a Mac with trusted local users and processes. See [proxy security](proxy/README.md#state-logs-and-security).

</details>

## License

MIT — see [LICENSE](LICENSE). Bundled Node.js notices are included in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

CodexMulti is an independent open-source project. It is not affiliated with or endorsed by OpenAI.
Codex is a trademark of OpenAI.

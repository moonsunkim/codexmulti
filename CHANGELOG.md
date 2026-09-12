# Changelog

All notable changes to CodexMulti will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.3]

### Fixed
- Load saved accounts in Developer ID releases by recognizing the distribution signing identity as well as the existing local signing identity.
- Show a startup error when the account service cannot start, instead of displaying an empty account list.
- Suppress background login-keychain authorization dialogs and preserve existing backups when access is denied.
- Verify real signed-app startup and saved-account loading before packaging a public release; the diagnostic probe no longer reports success for a failed runtime.

## [0.2.2]

### Fixed

- Keep still-valid accounts usable during temporary token-refresh outages; show a retry warning and clear it after recovery.
- Cancel upstream work and release account slots when a client disconnects before response headers, with bounded HTTP and WebSocket handshake waits.
- Create a private Codex config on first enable; accurately show unavailable proxy routing and restore direct connections from the main switch.
- Offer Repair during onboarding for an installed but unavailable service.
- Reject foreign Host and browser-origin traffic and protect the control API with a private per-user capability.
- Try the full eligible account pool after definitive pre-handshake WebSocket usage limits.
- Translate shell settings, menus, dialogs and accessibility labels through the core Korean catalog.
- Flush reset records and their parent directory before allowing a reset to be sent.

### Added

- A signed uninstall helper that restores managed Codex routing, drains requests and removes the verified LaunchAgent while retaining account data; Homebrew runs it before removal.
- Swift app builds, shell tests and distribution-script checks in CI. Public release now requires successful CI, Developer ID signing and Apple notarization.

## [0.2.1]

### Added

- Releases are now signed with a Developer ID certificate and notarized by Apple, so the first launch opens directly on macOS.
- Added proactive token renewal: the proxy refreshes access tokens that expire within 48 hours ahead of time, backs off on failure, and reports renewal status; an account whose renewal keeps failing says "Refresh failed · sign in again".
- Added a Keychain backup of each account's credentials that is restored automatically if the account's files go missing, and kept in sync after every refresh.
- Added WebSocket passthrough in the proxy, which Codex remote control and the CLI's streaming transport need.
- Added the remaining pool capacity to the toolbar capsule and the menu bar ("pool 47%", "Pool 47% left · 4 of 9 usable").
- Added a first-run checklist — add an account, install the proxy service, turn on routing — that tracks completion and disappears when done.
- Added Korean, with a Language setting (System, English, 한국어).
- Added a menu-bar icon drawn from the app's mark.
- Added the CodexMulti menu-bar app for using multiple Codex accounts with automatic failover after a confirmed weekly usage limit.
- Added a bundled, loopback-only proxy and Node.js v26.8.1, so no separate proxy or system Node.js installation is required.
- Added a branded app icon, README hero, and light and dark product screenshots.
- Added a visible app version with a monotonically increasing build number.
- Added the bundled Node.js license to the app and documented it in `THIRD_PARTY_NOTICES.md`.

### Changed

- Renamed the project, app, on-device storage, logs, service, and bundled commands to CodexMulti.
- Account rows can be dragged into a preferred order, which is preserved and applied to failover immediately.
- Simplified Settings around the controls users own and removed paths and connection details managed by the app.
- Codex CLI compatibility now uses a minimum supported version instead of requiring one exact version.

### Fixed

- Opening CodexMulti or an account action from the menu bar now brings the existing window and any requested sheet to the front.
- Sign-in now works when the Codex CLI was installed with npm by making the bundled Node.js runtime available during login.
- Fixed account dragging that could move the wrong account or appear to snap back.
- Reworked the first-run empty screen and menu-bar status to show actionable account and proxy states instead of ambiguous status text.

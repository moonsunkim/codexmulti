# Changelog

All notable changes to CodexMulti will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

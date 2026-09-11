# app — the SwiftUI shell

The shipping macOS app: a menu-bar item plus one window, drawn entirely from the projection the Zig
core in [`../core`](../core) hands over the `cm.bridge/1` C ABI. The shell owns windows, menus,
sheets, accessibility and macOS lifecycle. It owns no product state: every number and sentence it
draws comes from the core, apart from the dialog copy in `Sources/CodexMulti/Accounts/Copy.swift`.

Tests run headless — `CODEXMULTI_TEST_HEADLESS=1 swift test`. Plain `swift test` opens windows.

Start at the [repository README](../README.md).

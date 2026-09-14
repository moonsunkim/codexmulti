# app — the SwiftUI shell

The shipping macOS app: a menu-bar item plus one window. Account and usage views use the projection
the Zig core in [`../core`](../core) hands over the `cm.bridge/1` C ABI. The shell owns windows, menus,
sheets, accessibility and macOS lifecycle. The Zig core owns account and usage state and the shared
translation catalog, including menu and dialog copy. The Swift shell also coordinates native app
updates through `Sources/CodexMulti/App/UpdateController.swift` and the shared [`UpdaterKit`](../updater).

Tests run headless — `CODEXMULTI_TEST_HEADLESS=1 swift test`. Plain `swift test` opens windows.

## README screenshots

Run `./app/scripts/screenshots.sh` from the repository root after building. It renders the account
list, account details and preference controls off screen using synthetic fixtures. Account-row
percentages are used capacity; the menu's pool percentage is an average of weekly remaining capacity.

To capture a verified release bundle instead of the staging build:

```sh
CODEXMULTI_SCREENSHOT_BUNDLE="/path/to/CodexMulti.app" ./app/scripts/screenshots.sh
```

The executable stays inside its bundle so signed releases retain their signing context. Capture mode
requires a fixture, skips live services and the updater, and does not create a status item or activate
a window. The preference screenshot shows the controls above About; update behavior is documented
in the repository README. The menu images are native menu previews with synthetic accounts.

The README uses [`accounts-showcase.png`](../assets/screenshots/accounts-showcase.png) to show
both themes together regardless of the reader's page theme. It is a ChatGPT-generated presentation
based on the synthetic account captures. The original light and dark screenshots remain linked
below it. The screenshot script refreshes those native captures; it does not regenerate the showcase.

Start at the [repository README](../README.md).

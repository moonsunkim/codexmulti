# Contributing to CodexMulti

Thank you for helping improve CodexMulti.

## Before you start

For substantial changes, open an issue first. This gives maintainers and contributors a place to agree on the problem, scope, and user-facing behavior before implementation begins.

CodexMulti targets Apple Silicon Macs running macOS 26 or later. The canonical prerequisites, build steps, and test commands are maintained in the README's [Build from source](README.md#build-from-source) section. Follow that section rather than copying commands from older documentation.

The shell test command must be run from `app/` as `CODEXMULTI_TEST_HEADLESS=1 swift test`. Never run plain `swift test`, because it opens windows.

## Project rules

1. The core owns every user-facing string. Add or change text in the `core/src/strings.zig` catalogue; the SwiftUI shell only renders the text it receives.
2. Every bug fix starts with a reproduction test that fails, followed by the fix that makes it pass.
3. Do not add comments to code, scripts, or workflow YAML.
4. Never edit bridge fixtures by hand. Regenerate them with `zig build export-fixtures`, then run `app/scripts/sync-fixtures.sh --sync`.

## Pull requests

Keep pull requests focused. Explain what changed and why it matters to users. Include the exact reproduction test name and evidence that it failed before the fix and passed afterward.

Before requesting review, confirm that:

- The applicable build and test commands from the README pass.
- Every bug fix includes red-to-green reproduction evidence.
- Generated fixtures were regenerated and synchronized when affected, never edited by hand.
- No code, script, or workflow comments were added.
- Every changed user-facing string comes from `core/src/strings.zig`.

## Commit messages

Write a concise, one-line subject. Use the body to explain why the change is needed, including relevant behavior and tradeoffs, rather than repeating the diff.

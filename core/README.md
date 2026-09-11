# CodexMulti core

This directory holds the Zig core used by the SwiftUI shell in `../app`. It
builds the relocatable `cmcore.o` object, exposes the `cm.bridge/1` JSON ABI,
and owns the core and bridge contract tests. The retired CodexMulti menu-bar
shell and its npm toolchain are not part of this repository.

- C ABI: `include/cmcore.h` and `src/cmcore.zig`.
- Bridge protocol: `src/bridge_json.zig` and `src/shell_model.zig`.
- Shared projection: `src/ui_model.zig`, `src/ui_contracts.zig`,
  `src/ui_projection.zig`, `src/ui_format.zig`, and `src/ui_reset.zig`.
- Application service: `src/app_service.zig`, coordinator, provider/auth,
  Keychain, proxy, routing, runtime-path, and persistence modules.
- Golden contract data: `fixtures/bridge/*`.

## Commands

Zig 0.16.0 is the only build dependency for the core and its tests:

```sh
zig build cmcore -Doptimize=ReleaseSafe -Dtarget=aarch64-macos \
  -Dcore-provenance=CODEXMULTI_CORE_SRC_SHA256=TEST
zig build test
zig build test-bridge --summary all
zig build export-fixtures
```

`cmcore` installs `zig-out/lib/cmcore.o`. `export-fixtures` is a deliberate
contract operation: its output must leave `fixtures/bridge/*` unchanged unless
a coordinated `cm.bridge/1` schema change is intended.

## Documentation

- [Architecture]the design notes: surfaces, service boundaries,
  providers, storage, concurrency, reset safety, and passive I/O.
- [Naming and continuity]the design notes: names that are presentation-only and
  identifiers that must remain byte-for-byte stable.
- [Operations]the design notes: safe local build and fixture procedures.
- [Testing]the design notes: the SDK-free aggregate and bridge gate topology.

## Safety contract

- Provider and login I/O starts only after an explicit user command.
- Projection and pump operations do not originate provider work.
- Proxy status/switch/pause/reload/sync occur only after their explicit UI
  actions; current-run v2 mappings own Codex switching without local fallback.
- Concurrency remains globally two operations and one per account; workers are
  canceled-and-joined before borrowed state is released.
- Durable app documents contain no credential material.
- Reset redemption requires a fresh preflight, two-step confirmation,
  durable-before-send state, same-key retry, and a verification read.
- Storage, Keychain, proxy-service, and designated-requirement identifiers are
  compatibility data and must not be renamed as presentation cleanup.

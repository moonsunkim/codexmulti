# Updater release configuration

The app uses Sparkle 2.9.6 for app replacement and a separate signed native coordinator for runtime
activation. Release publishing is a separate operation from implementing or testing this feature.

## Signing and feed

Configure these values before publishing the first updater-enabled release:

| Value | Storage | Purpose |
| --- | --- | --- |
| `SPARKLE_PUBLIC_KEY` | GitHub repository variable; build environment locally | Base64-encoded 32-byte Ed25519 public key pinned in Info.plist |
| `SPARKLE_PRIVATE_KEY` | GitHub Actions secret | Base64-encoded 32-byte private seed exported by Sparkle's `generate_keys` |
| `SPARKLE_PRIVATE_KEY_FILE` | Local environment or ephemeral CI path | Private seed file with mode 0600, read by the signing tool |
| `SPARKLE_FEED_URL` | Optional build environment | HTTPS feed; public release default is the repository's `releases/latest/download/appcast.xml` |

The Sparkle distribution under `app/.build/artifacts/sparkle/Sparkle/bin/` includes `generate_keys`,
`sign_update` and `generate_appcast`. Create an organization-specific key once, retain it securely,
and export it using the tool's file option. Do not put the private seed in a command argument, git,
release notes or an app bundle. Key rotation requires a separate compatibility plan.

`build-app.sh` records content hashes before signing. Packaging signs Node, maintenance, the runtime
launcher, the update agent, Sparkle's nested executables/services/framework, then the outer app.
It refreshes signed-file hashes without changing runtime identity. Runtime identity includes the
proxy tree, unsigned Node, launcher and coordinator content, architecture and activation revision.
GUI-only changes do not change this identity. The immutable runtime retains the whole signed app
so nested resource seals remain verifiable.

`release.sh` requires the public/private update key pair for public releases. It verifies that the
private key matches the public key embedded in the app, signs the final notarized ZIP and appcast,
and verifies both signatures. `SURequireSignedFeed` and its required companion
`SUVerifyUpdateBeforeExtraction` are both enabled; the feed generator rejects a bundle missing the
latter. The feed includes the runtime ID and update protocol. ZIP, checksum,
runtime manifest and feed belong to one build. Publishing uploads the payload to a draft release,
uploads the feed afterward, and only then makes the release public. Partial existing releases are
refused rather than combined with another build.

A local dry run without a Sparkle key can still produce a signed test app; it does not produce a
publishable update feed. Automatic downloads and installation are disabled in the app. Update
checks are initiated from Settings; no OS notification is used.

## Verification

Run the Node proxy tests, the Zig core aggregate, the updater Swift package and the app's headless
Swift tests. Native runtime tests use two signed app fixtures, separate temporary data and a unique
`dev.codexmulti.tests.*` LaunchAgent. Never substitute the production label or port 8787.

```sh
CODEXMULTI_TEST_HEADLESS=1 swift test --package-path updater
SIGNING_IDENTITY='Developer ID Application: Your Team (TEAMID)' \
  updater/scripts/prepare-native-fixtures.sh /private/tmp/signed-candidate.app /private/tmp/native-fixtures
CODEXMULTI_TEST_HEADLESS=1 \
  CODEXMULTI_UPDATER_TEST_OLD_APP=/private/tmp/native-fixtures/old.app \
  CODEXMULTI_UPDATER_TEST_NEW_APP=/private/tmp/native-fixtures/new.app \
  CODEXMULTI_UPDATER_TEST_GUI_APP=/private/tmp/native-fixtures/gui.app \
  swift test --package-path updater --filter Native
node --test app/scripts/tests/appcast.test.mjs
```

The two fixtures must have different valid runtime IDs and pass the pinned Developer ID requirement.
The test creates and removes only its own label and data. It verifies that an incomplete HTTP body
keeps the old process alive and that the actual signed launcher and Node process switch only after
the connection finishes. Unit coverage additionally exercises OAuth refreshes, quiet WebSockets,
lease expiry, stale identities, cancellation, Off, coordinator recreation, lost activation replies,
pre-admission rollback, and rollback after an OS-confirmed candidate crash.

The native agent check rejects an untrusted same-user process, accepts a signed GUI peer, kills only
its own coordinator PID, and verifies launchd recovery with the installation still armed. It then
acknowledges an early download abort and checks process exit plus LaunchAgent file removal. The
native runtime check also confirms that Off waits for a partial HTTP request and removes autostart.
Cancellation and rollback retain a deferred build/runtime record across later service commands;
GUI restart does not retry that build. Settings provides an explicit engine-apply action.

`activation_revision` must increase for changes to maintenance behavior that affect runtime
activation or its persisted artifacts. GUI copy, app version and signing time alone do not justify
changing it. The pinned Developer ID requirement currently belongs to the CodexMulti release team;
the fixture identity must satisfy that requirement. These fixtures are local test apps, not releases.

Keep signature validation, actual process/runtime identity, GUI readiness and successful provider
requests distinct when reporting verification. A proxy health response is not proof of a complete
Sparkle GUI install. The first public end-to-end install should use two release-signed builds and a
controlled feed before broad distribution.

## Isolated Sparkle installation check

The fixture compiles the production `UpdateController.swift` unchanged into a small signed AppKit
host. It uses the real Sparkle framework, archive and feed signatures, native update agent, immutable
launcher, Node proxy, and managed plist renderer. It creates two app builds under a private temporary
directory and installs the second over the first through Sparkle. Each test has its own HOME, defaults
domain, loopback port and LaunchAgent label. The bundle keeps the production signing requirement;
there is no signature or peer-authentication bypass.

```sh
SIGNING_IDENTITY='Developer ID Application: Your Team (TEAMID)' \
  bash updater/scripts/prepare-sparkle-fixture.sh /private/tmp/signed-candidate.app \
  /private/tmp/codexmulti-sparkle-ui-check ui
python3 updater/scripts/run-sparkle-fixture.py /private/tmp/codexmulti-sparkle-ui-check
SIGNING_IDENTITY='Developer ID Application: Your Team (TEAMID)' \
  bash updater/scripts/prepare-sparkle-fixture.sh /private/tmp/signed-candidate.app \
  /private/tmp/codexmulti-sparkle-runtime-check runtime
python3 updater/scripts/run-sparkle-fixture.py /private/tmp/codexmulti-sparkle-runtime-check
```

The UI case must preserve the proxy boot ID and open request throughout actual app replacement and
relaunch. The runtime case must relaunch the new GUI, remain in `WAITING_IDLE` with the original proxy
while a partial request is open, and reach `COMPLETE` with the new runtime and generation after the
test closes the request. Both cases verify a different GUI PID and unchanged synthetic authentication.
The runner removes only its own running jobs and leaves its fixtures and receipts for inspection.

Transport is a test-only `URLProtocol` adapter installed into the fixture process's default URLSession
configuration. It supplies local bytes for the fixture's HTTPS URLs; it does not validate public DNS,
TLS or release hosting. The fixture's `CoreProtocol` records shutdown/start ordering and does not run
the production Zig bridge. Thus this check proves the real controller's installation handoff and
Sparkle's replacement/relaunch, with native runtime switching, rather than every full-app startup
side effect. Production core and shell tests remain separate. Physical reboot/sleep and a public
notarized release still require their own release validation.

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
OUTPUT="$REPO_ROOT/dist/updater-candidate"
APP=/private/tmp/codexmulti-updater-candidate.app
test -n "${SIGNING_IDENTITY:-}"
test -n "${SPARKLE_PUBLIC_KEY:-}"
test -n "${SPARKLE_FEED_URL:-}"
test -f "${SPARKLE_PRIVATE_KEY_FILE:-}"
test -f "${APPLE_NOTARY_KEY_PATH:-}"
test ! -e "$APP"
mkdir -p "$OUTPUT"
"$SCRIPT_DIR/package-signed-macos.sh" --stage "$APP"
"$SCRIPT_DIR/verify-signed-startup.sh" "$APP"
"$SCRIPT_DIR/verify-bundled-proxy.sh" "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/notary-submission.zip"
xcrun notarytool submit "$OUTPUT/notary-submission.zip" --key "$APPLE_NOTARY_KEY_PATH" \
    --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait --output-format json \
    > "$OUTPUT/notarization.json"
python3 - "$OUTPUT/notarization.json" <<'PY'
import json
import sys
assert json.load(open(sys.argv[1]))['status'] == 'Accepted'
PY
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
/usr/sbin/spctl --assess --type execute -vv "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
"$SCRIPT_DIR/verify-signed-startup.sh" "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/CodexMulti.zip"
shasum -a 256 "$OUTPUT/CodexMulti.zip" > "$OUTPUT/CodexMulti.zip.sha256"
cp "$APP/Contents/Resources/runtime-manifest.json" "$OUTPUT/runtime-manifest.json"
node "$SCRIPT_DIR/create-appcast.mjs" "$APP" "$OUTPUT/CodexMulti.zip" "$OUTPUT/appcast.xml" \
    https://example.invalid/updater-candidate/CodexMulti.zip "$SPARKLE_PRIVATE_KEY_FILE" \
    "$REPO_ROOT/app/.build/artifacts/sparkle/Sparkle/bin/sign_update"
python3 - "$APP" "$OUTPUT" <<'PY'
import json
import pathlib
import plistlib
import subprocess
import sys
app = pathlib.Path(sys.argv[1])
output = pathlib.Path(sys.argv[2])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
receipt = dict(commit=subprocess.check_output(['git','rev-parse','HEAD'], text=True).strip(),
    version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
    public_key=info['SUPublicEDKey'], feed_url=info['SUFeedURL'], notarized=True,
    stapled=True, gatekeeper_accepted=True, signed_core_startup_verified=True,
    appcast_signature_verified=True, public_release=False)
(output / 'verified.json').write_text(json.dumps(receipt, indent=2) + '\n')
(output / 'notary-submission.zip').unlink()
PY

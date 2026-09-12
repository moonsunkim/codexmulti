#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
FIXTURE=/private/tmp/codexmulti-sparkle-notarized-fixture
OUTPUT="$REPO_ROOT/dist/updater-candidate/sparkle-hosted-fixture"
test -n "${CODEXMULTI_SPARKLE_TEST_FEED_BASE:-}"
test ! -e "$FIXTURE"
mkdir -p "$OUTPUT/Feed"
bash "$REPO_ROOT/updater/scripts/prepare-sparkle-fixture.sh" \
    /private/tmp/codexmulti-updater-candidate.app "$FIXTURE" runtime
mkdir "$FIXTURE/NotaryPayload"
/usr/bin/ditto "$FIXTURE/Installed/CodexMulti.app" "$FIXTURE/NotaryPayload/Old.app"
/usr/bin/ditto "$FIXTURE/Feed/CodexMulti.app" "$FIXTURE/NotaryPayload/New.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$FIXTURE/NotaryPayload" "$FIXTURE/notary-submission.zip"
xcrun notarytool submit "$FIXTURE/notary-submission.zip" --key "$APPLE_NOTARY_KEY_PATH" \
    --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait --output-format json \
    > "$OUTPUT/notarization.json"
python3 - "$OUTPUT/notarization.json" <<'PY'
import json
import sys
assert json.load(open(sys.argv[1]))['status'] == 'Accepted'
PY
for app in "$FIXTURE/Installed/CodexMulti.app" "$FIXTURE/Feed/CodexMulti.app"; do
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    /usr/sbin/spctl --assess --type execute -vv "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
done
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$FIXTURE/Installed/CodexMulti.app" "$OUTPUT/old-app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$FIXTURE/Feed/CodexMulti.app" "$OUTPUT/Feed/CodexMulti.zip"
node "$SCRIPT_DIR/create-appcast.mjs" "$FIXTURE/Feed/CodexMulti.app" "$OUTPUT/Feed/CodexMulti.zip" \
    "$OUTPUT/Feed/appcast.xml" "$CODEXMULTI_SPARKLE_TEST_FEED_BASE/CodexMulti.zip" "$FIXTURE/signing-key" \
    "$REPO_ROOT/app/.build/artifacts/sparkle/Sparkle/bin/sign_update"
cp "$FIXTURE/plan.json" "$OUTPUT/plan.json"
rm "$FIXTURE/signing-key"
printf 'Two notarized Sparkle fixtures packaged for HTTPS installation verification.\n'

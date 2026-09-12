#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SOURCE_APP="${1:?signed source app is required}"
OUTPUT="${2:?new output directory is required}"
KIND="${3:-ui}"
FEED_BASE="${CODEXMULTI_SPARKLE_TEST_FEED_BASE:-https://sparkle.codexmulti.test}"
test -n "${SIGNING_IDENTITY:-}"
test "$KIND" = ui || test "$KIND" = runtime
test ! -e "$OUTPUT"
mkdir -m 0700 "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
mkdir "$OUTPUT/Installed" "$OUTPUT/Feed"
APP="$OUTPUT/Installed/CodexMulti.app"
/usr/bin/ditto "$SOURCE_APP" "$APP"
swift build -c release --package-path "$REPO_ROOT/updater"
BUILD="$(swift build -c release --package-path "$REPO_ROOT/updater" --show-bin-path)"
SPARKLE="$REPO_ROOT/app/.build/artifacts/sparkle/Sparkle"
swiftc -parse-as-library -I "$BUILD/Modules" \
    -F "$SPARKLE/Sparkle.xcframework/macos-arm64_x86_64" \
    "$REPO_ROOT/app/Sources/CodexMulti/App/UpdateController.swift" \
    "$REPO_ROOT/updater/Tests/Fixtures/SparkleInstallProbe.swift" \
    "$BUILD"/UpdaterKit.build/*.swift.o -framework Security -framework AppKit -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$APP/Contents/MacOS/CodexMulti"
for helper in codexmulti-update-agent codexmulti-runtime-launcher; do
    cp "$BUILD/$helper" "$APP/Contents/Helpers/$helper"
done
node --input-type=module - "$OUTPUT" <<'JS'
import { randomBytes, createPrivateKey, createPublicKey } from 'node:crypto';
import { writeFileSync } from 'node:fs';
const root = process.argv[2];
const seed = randomBytes(32);
writeFileSync(`${root}/signing-key`, seed.toString('base64'), { mode: 0o600 });
const privateKey = createPrivateKey({ key: Buffer.concat([Buffer.from('302e020100300506032b657004220420', 'hex'), seed]), format: 'der', type: 'pkcs8' });
writeFileSync(`${root}/public-key`, createPublicKey(privateKey).export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64'));
JS
python3 - "$OUTPUT" "$KIND" "$REPO_ROOT/app/Resources/Info.plist" "$FEED_BASE" <<'PY'
import json
import pathlib
import plistlib
import socket
import sys
import time
import uuid
from urllib.parse import urlsplit

root = pathlib.Path(sys.argv[1])
info_path = root / 'Installed/CodexMulti.app/Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
old_build = str(int(time.time()) * 10)
base = sys.argv[4].rstrip('/')
parsed = urlsplit(base)
assert parsed.scheme == 'https' and parsed.hostname and not parsed.query and not parsed.fragment
info.update(CFBundleVersion=old_build, SUFeedURL=base + '/appcast.xml',
            SUPublicEDKey=(root / 'public-key').read_text(), SURequireSignedFeed=True)
source_info = pathlib.Path(sys.argv[3])
info['SUVerifyUpdateBeforeExtraction'] = plistlib.loads(source_info.read_bytes())['SUVerifyUpdateBeforeExtraction']
info['SUDefaultsDomain'] = 'dev.codexmulti.tests.sparkle.' + str(uuid.uuid4())
info_path.write_bytes(plistlib.dumps(info))
with socket.socket() as server:
    server.bind(('127.0.0.1', 0))
    port = server.getsockname()[1]
plan = dict(label='dev.codexmulti.tests.sparkle.' + str(uuid.uuid4()), port=port,
            oldBuild=old_build, newBuild=str(int(old_build) + 1), changedRuntime=sys.argv[2] == 'runtime',
            transport='local' if parsed.hostname == 'sparkle.codexmulti.test' else 'https')
(root / 'plan.json').write_text(json.dumps(plan, indent=2) + '\n')
PY
node "$REPO_ROOT/app/scripts/runtime-manifest.mjs" "$APP" create
for helper in codexmulti-update-agent codexmulti-runtime-launcher; do
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP/Contents/Helpers/$helper"
done
node "$REPO_ROOT/app/scripts/runtime-manifest.mjs" "$APP" signed
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP"
/usr/bin/ditto "$APP" "$OUTPUT/Feed/CodexMulti.app"
python3 - "$OUTPUT" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

root = pathlib.Path(sys.argv[1])
plan = json.loads((root / 'plan.json').read_text())
app = root / 'Feed/CodexMulti.app'
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleVersion'] = plan['newBuild']
info_path.write_bytes(plistlib.dumps(info))
manifest_path = app / 'Contents/Resources/runtime-manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['app_build'] = plan['newBuild']
if plan['changedRuntime']:
    manifest['activation_revision'] += 1
    keys = ['architecture', 'proxy_tree_sha256', 'node_content_sha256', 'launcher_content_sha256', 'agent_content_sha256', 'activation_revision']
    identity = 'codexmulti-runtime-v1\n' + ''.join(str(manifest[key]) + '\n' for key in keys)
    manifest['runtime_id'] = hashlib.sha256(identity.encode()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
PY
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$OUTPUT/Feed/CodexMulti.app"
for app in "$APP" "$OUTPUT/Feed/CodexMulti.app"; do
    /usr/bin/codesign --verify --deep --strict "$app"
done
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$OUTPUT/Feed/CodexMulti.app" "$OUTPUT/Feed/CodexMulti.zip"
node "$REPO_ROOT/app/scripts/create-appcast.mjs" "$OUTPUT/Feed/CodexMulti.app" "$OUTPUT/Feed/CodexMulti.zip" \
    "$OUTPUT/Feed/appcast.xml" "$FEED_BASE/CodexMulti.zip" "$OUTPUT/signing-key" "$SPARKLE/bin/sign_update"
printf 'Signed Sparkle fixture: %s\n' "$OUTPUT"

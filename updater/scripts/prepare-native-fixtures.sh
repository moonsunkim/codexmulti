#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
SOURCE_APP="${1:?signed source app is required}"
OUTPUT="${2:?new output directory is required}"
test -n "${SIGNING_IDENTITY:-}"
test ! -e "$OUTPUT"
mkdir -m 0700 "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd -P)"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT/old.app"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT/new.app"
/usr/bin/ditto "$SOURCE_APP" "$OUTPUT/gui.app"
python3 - "$OUTPUT/new.app" <<'PY'
import hashlib
import json
import pathlib
import plistlib
import sys

app = pathlib.Path(sys.argv[1])
info_path = app / 'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['CFBundleVersion'] = str(int(info['CFBundleVersion']) + 1)
info_path.write_bytes(plistlib.dumps(info))
manifest_path = app / 'Contents/Resources/runtime-manifest.json'
manifest = json.loads(manifest_path.read_text())
manifest['app_build'] = info['CFBundleVersion']
manifest['activation_revision'] += 1
keys = ['architecture', 'proxy_tree_sha256', 'node_content_sha256', 'launcher_content_sha256', 'agent_content_sha256', 'activation_revision']
identity = 'codexmulti-runtime-v1\n' + ''.join(str(manifest[key]) + '\n' for key in keys)
manifest['runtime_id'] = hashlib.sha256(identity.encode()).hexdigest()
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
PY
swift build --package-path "$REPO_ROOT/updater"
BUILD="$(swift build --package-path "$REPO_ROOT/updater" --show-bin-path)"
swiftc -I "$BUILD/Modules" "$REPO_ROOT/updater/Tests/Fixtures/AgentClient.swift" \
    "$BUILD"/UpdaterKit.build/*.swift.o -framework Security \
    -o "$OUTPUT/gui.app/Contents/MacOS/CodexMulti"
/usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$OUTPUT/gui.app/Contents/MacOS/CodexMulti"
for app in "$OUTPUT/new.app" "$OUTPUT/gui.app"; do
    /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
done
printf 'Signed native fixtures: %s\n' "$OUTPUT"

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
CORE_DIR="${CODEXMULTI_CORE_DIR:-$REPO_ROOT/core}"
CORE_DIR="$(cd "$CORE_DIR" && pwd -P)"
PROXY_SRC="${PROXY_SRC:-$REPO_ROOT/proxy}"
NODE_SRC="${NODE_SRC:-$PROJECT_DIR/.node/v26.8.1/bin/node}"
CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
STRINGS_BIN="${STRINGS_BIN:-/usr/bin/strings}"
NM_BIN="${NM_BIN:-/usr/bin/nm}"
OTOOL_BIN="${OTOOL_BIN:-/usr/bin/otool}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
DIFF_BIN="${DIFF_BIN:-/usr/bin/diff}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"
STAT_BIN="${STAT_BIN:-/usr/bin/stat}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    printf 'Usage: scripts/verify-provenance.sh [--require-clean] <CodexMulti.app>\n' >&2
}

require_tool() {
    test -x "$1" || die "required tool is unavailable: $1"
}

plist_value() {
    "$PLUTIL_BIN" -extract "$2" raw -o - "$1/Contents/Info.plist" 2>/dev/null
}

marker_value() {
    local name count
    name="$1"
    count="$(awk -v prefix="$name=" 'index($0, prefix) == 1 { count += 1 } END { print count + 0 }' "$proxy_provenance")"
    test "$count" = "1" ||
        die "bundled proxy PROVENANCE must contain exactly one $name marker (found $count)"
    awk -v prefix="$name=" 'index($0, prefix) == 1 { print substr($0, length(prefix) + 1) }' "$proxy_provenance"
}

marker_count() {
    local name
    name="$1"
    awk -v prefix="$name=" 'index($0, prefix) == 1 { count += 1 } END { print count + 0 }' "$proxy_provenance"
}

proxy_tree_sha256() {
    local proxy_root manifest_path status digest relative mode size file_sha
    proxy_root="$1"
    manifest_path="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-proxy-manifest.XXXXXX")"
    status=0
    (
        cd "$proxy_root"
        find package.json bin src -type f -print0 | LC_ALL=C sort -z |
            while IFS= read -r -d '' relative; do
                mode="$("$STAT_BIN" -f %Lp "$relative")"
                size="$("$STAT_BIN" -f %z "$relative")"
                file_sha="$("$SHASUM_BIN" -a 256 "$relative" | awk '{print $1}')"
                printf '%s\t%s\t%s\t%s\n' "$relative" "$mode" "$size" "$file_sha"
            done
    ) > "$manifest_path" || status=$?
    if test "$status" -ne 0; then
        /bin/rm -f -- "$manifest_path"
        return "$status"
    fi
    digest="$("$SHASUM_BIN" -a 256 "$manifest_path" | awk '{print $1}')"
    /bin/rm -f -- "$manifest_path"
    printf '%s\n' "$digest"
}

require_clean=no
if test "${1:-}" = "--require-clean"; then
    require_clean=yes
    shift
fi
test "$#" -eq 1 || { usage; exit 2; }
app="$1"
executable="$app/Contents/MacOS/CodexMulti"
bundled_node="$app/Contents/Helpers/node"
bundled_node_license="$app/Contents/Resources/Licenses/Node.LICENSE"
bundled_proxy="$app/Contents/Resources/proxy"
proxy_provenance="$bundled_proxy/PROVENANCE"
source_list="$CORE_DIR/scripts/core-source-list.txt"
version_file="$REPO_ROOT/VERSION"

require_tool "$SHASUM_BIN"
require_tool "$STRINGS_BIN"
require_tool "$NM_BIN"
require_tool "$OTOOL_BIN"
require_tool "$PLUTIL_BIN"
require_tool "$DIFF_BIN"
require_tool "$CMP_BIN"
require_tool "$STAT_BIN"
test -d "$app" || die "candidate app does not exist: $app"
test -f "$executable" || die "candidate executable does not exist: $executable"
test -s "$source_list" || die "core source list is missing or empty: $source_list"
test -s "$version_file" || die "VERSION file is missing or empty: $version_file"
test -d "$PROXY_SRC" || die "proxy source directory is missing: $PROXY_SRC"
PROXY_SRC="$(cd "$PROXY_SRC" && pwd -P)"
case "$PROXY_SRC" in
    "$REPO_ROOT"/*) ;;
    *) die "PROXY_SRC must be inside the monorepo: $PROXY_SRC" ;;
esac
test "$(git -C "$PROXY_SRC" rev-parse --show-toplevel 2>/dev/null || true)" = "$REPO_ROOT" ||
    die "PROXY_SRC must belong to the monorepo checkout: $PROXY_SRC"
proxy_relative="${PROXY_SRC#"$REPO_ROOT"/}"
test -f "$NODE_SRC" || die "Node source is missing or not a regular file target: $NODE_SRC"
test -x "$NODE_SRC" || die "Node source is not executable: $NODE_SRC"
test -f "$bundled_node" || die "bundled Node runtime is missing: $bundled_node"
test -x "$bundled_node" || die "bundled Node runtime is not executable: $bundled_node"
test ! -L "$bundled_node" || die "bundled Node runtime must not be a symlink"
test -s "$bundled_node_license" || die "bundled Node license is missing or empty: $bundled_node_license"
test ! -L "$bundled_node_license" || die "bundled Node license must not be a symlink"
test -d "$bundled_proxy/bin" || die "bundled proxy bin directory is missing"
test -d "$bundled_proxy/src" || die "bundled proxy src directory is missing"
test -f "$bundled_proxy/package.json" || die "bundled proxy package.json is missing"
test -x "$bundled_proxy/bin/codexmulti-proxy" || die "bundled proxy entrypoint is missing or not executable"
test -f "$proxy_provenance" || die "bundled proxy PROVENANCE file is missing"

if test "$require_clean" = yes; then
    test -z "$(git -C "$REPO_ROOT" status --porcelain)" || die "monorepo checkout is not clean"
fi

app_signature_details="$("$CODESIGN_BIN" -d --verbose=4 "$app" 2>&1 || true)"
if printf '%s\n' "$app_signature_details" | grep -F -x 'Signature=adhoc' >/dev/null; then
    bundle_signed=no
elif printf '%s\n' "$app_signature_details" | grep -Eq '^Signature size=[0-9]+$'; then
    bundle_signed=yes
else
    die "cannot determine whether the candidate app has a packaging signature"
fi

recorded_app_version="$(marker_value CODEXMULTI_APP_VERSION)"
recorded_build_number="$(marker_value CODEXMULTI_BUILD_NUMBER)"
recorded_proxy_commit="$(marker_value CODEXMULTI_PROXY_COMMIT)"
recorded_proxy_tree_sha="$(marker_value CODEXMULTI_PROXY_TREE_SHA256)"
recorded_node_version="$(marker_value CODEXMULTI_NODE_VERSION)"
recorded_node_sha="$(marker_value CODEXMULTI_NODE_SHA256)"
if test "$bundle_signed" = yes; then
    recorded_signed_node_sha="$(marker_value CODEXMULTI_SIGNED_NODE_SHA256)"
else
    signed_marker_count="$(marker_count CODEXMULTI_SIGNED_NODE_SHA256)"
    test "$signed_marker_count" = "0" ||
        die "unsigned bundle PROVENANCE must not contain CODEXMULTI_SIGNED_NODE_SHA256 (found $signed_marker_count)"
    recorded_signed_node_sha=""
fi

printf '%s\n' "$recorded_app_version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$' || die "PROVENANCE app version is invalid"
printf '%s\n' "$recorded_build_number" | grep -Eq '^[0-9]{12}$' || die "PROVENANCE build number is not a 12-digit UTC timestamp"
printf '%s\n' "$recorded_proxy_commit" | grep -Eq '^[0-9a-f]{40}$' || die "PROVENANCE proxy commit is not 40 lowercase hex characters"
printf '%s\n' "$recorded_proxy_tree_sha" | grep -Eq '^[0-9a-f]{64}$' || die "PROVENANCE proxy tree SHA-256 is not 64 lowercase hex characters"
printf '%s\n' "$recorded_node_version" | grep -Eq '^v.+' || die "PROVENANCE Node version does not start with v"
printf '%s\n' "$recorded_node_sha" | grep -Eq '^[0-9a-f]{64}$' || die "PROVENANCE Node SHA-256 is not 64 lowercase hex characters"
if test "$bundle_signed" = yes; then
    printf '%s\n' "$recorded_signed_node_sha" | grep -Eq '^[0-9a-f]{64}$' ||
        die "PROVENANCE signed Node SHA-256 is not 64 lowercase hex characters"
fi

core_source_sha="$(cd "$CORE_DIR" && xargs "$SHASUM_BIN" -a 256 < "$source_list" | "$SHASUM_BIN" -a 256 | awk '{print $1}')"
printf '%s\n' "$core_source_sha" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate the core source SHA-256"
core_marker="CODEXMULTI_CORE_SRC_SHA256=$core_source_sha"
bridge_schema="$(plist_value "$app" CodexMultiBridgeSchema || true)"
test "$bridge_schema" = "1" || die "unsupported or unreadable CodexMultiBridgeSchema: ${bridge_schema:-missing}"
schema_marker="CODEXMULTI_BRIDGE_SCHEMA=$bridge_schema"
proxy_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$proxy_relative")"
node_version="$("$NODE_SRC" --version)"
node_root="$(cd "$(dirname "$NODE_SRC")/.." && pwd -P)"
node_license_src="$node_root/LICENSE"
bundled_node_version="$("$bundled_node" --version)"
node_sha="$("$SHASUM_BIN" -a 256 "$NODE_SRC" | awk '{print $1}')"
bundled_node_sha="$("$SHASUM_BIN" -a 256 "$bundled_node" | awk '{print $1}')"
plist_proxy_commit="$(plist_value "$app" CodexMultiProxyCommit || true)"
plist_node_version="$(plist_value "$app" CodexMultiNodeVersion || true)"
plist_app_version="$(plist_value "$app" CFBundleShortVersionString || true)"
plist_build_number="$(plist_value "$app" CFBundleVersion || true)"
expected_app_version="$(sed -n '1p' "$version_file")"
app_version_marker="CODEXMULTI_APP_VERSION=$recorded_app_version"
build_number_marker="CODEXMULTI_BUILD_NUMBER=$recorded_build_number"
proxy_marker="CODEXMULTI_PROXY_COMMIT=$proxy_commit"
proxy_tree_marker="CODEXMULTI_PROXY_TREE_SHA256=$recorded_proxy_tree_sha"
node_version_marker="CODEXMULTI_NODE_VERSION=$node_version"
node_sha_marker="CODEXMULTI_NODE_SHA256=$node_sha"
printf '%s\n' "$proxy_commit" | grep -Eq '^[0-9a-f]{40}$' || die "could not resolve the proxy commit"
printf '%s\n' "$node_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+' || die "Node source returned an invalid version"
test "${node_root##*/}" = "$node_version" || die "Node source is not stored under its version directory $node_version"
test -s "$node_license_src" || die "Node source license is missing or empty: $node_license_src"
test "$bundled_node_version" = "$node_version" || die "bundled Node version does not match NODE_SRC"
test "$recorded_app_version" = "$expected_app_version" || die "PROVENANCE app version does not match VERSION"
test "$recorded_build_number" = "$plist_build_number" || die "PROVENANCE build number does not match Info.plist"
test "$plist_app_version" = "$expected_app_version" || die "Info.plist app version does not match VERSION"
printf '%s\n' "$plist_build_number" | grep -Eq '^[0-9]{12}$' || die "Info.plist build number is not a 12-digit UTC timestamp"
test "$plist_proxy_commit" = "$proxy_commit" || die "Info.plist proxy commit does not match PROXY_SRC"
test "$plist_node_version" = "$node_version" || die "Info.plist Node version does not match NODE_SRC"
test "$recorded_proxy_commit" = "$proxy_commit" || die "PROVENANCE proxy commit does not match PROXY_SRC"
test "$recorded_node_version" = "$node_version" || die "PROVENANCE Node version does not match NODE_SRC"
test "$recorded_node_sha" = "$node_sha" || die "PROVENANCE unsigned Node SHA-256 does not match NODE_SRC"
"$CMP_BIN" -s "$node_license_src" "$bundled_node_license" || die "bundled Node license differs from the pinned Node source license"

if "$PLUTIL_BIN" -extract CodexMultiProxyTreeSHA256 raw -o - "$app/Contents/Info.plist" >/dev/null 2>&1; then
    test "$(plist_value "$app" CodexMultiProxyTreeSHA256)" = "$recorded_proxy_tree_sha" ||
        die "Info.plist proxy tree SHA-256 does not match PROVENANCE"
fi
if "$PLUTIL_BIN" -extract CodexMultiNodeSHA256 raw -o - "$app/Contents/Info.plist" >/dev/null 2>&1; then
    test "$(plist_value "$app" CodexMultiNodeSHA256)" = "$recorded_node_sha" ||
        die "Info.plist Node SHA-256 does not match PROVENANCE"
fi
if "$PLUTIL_BIN" -extract CodexMultiSignedNodeSHA256 raw -o - "$app/Contents/Info.plist" >/dev/null 2>&1; then
    test "$bundle_signed" = yes || die "unsigned bundle Info.plist must not contain CodexMultiSignedNodeSHA256"
    test "$(plist_value "$app" CodexMultiSignedNodeSHA256)" = "$recorded_signed_node_sha" ||
        die "Info.plist signed Node SHA-256 does not match PROVENANCE"
fi

proxy_entries="$(cd "$bundled_proxy" && find . -mindepth 1 -maxdepth 1 -print | sed 's#^\./##' | LC_ALL=C sort)"
test "$proxy_entries" = "$(printf 'PROVENANCE\nbin\npackage.json\nsrc\n')" ||
    die "bundled proxy contains missing or unexpected top-level entries"
test ! -L "$bundled_proxy/package.json" || die "bundled proxy package.json must not be a symlink"
test ! -L "$bundled_proxy/bin" || die "bundled proxy bin must not be a symlink"
test ! -L "$bundled_proxy/src" || die "bundled proxy src must not be a symlink"
unexpected_proxy_entry="$(cd "$bundled_proxy" && find package.json bin src ! \( -type d -o -type f \) -print -quit)"
test -z "$unexpected_proxy_entry" || die "bundled proxy contains a symlink or special file: $unexpected_proxy_entry"
computed_proxy_tree_sha="$(proxy_tree_sha256 "$bundled_proxy")"
printf '%s\n' "$computed_proxy_tree_sha" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate the bundled proxy tree SHA-256"
test "$computed_proxy_tree_sha" = "$recorded_proxy_tree_sha" ||
    die "PROVENANCE proxy tree SHA-256 does not match the bundled proxy tree"
"$CMP_BIN" -s "$PROXY_SRC/package.json" "$bundled_proxy/package.json" ||
    die "bundled proxy package.json differs from PROXY_SRC"
"$DIFF_BIN" -qr "$PROXY_SRC/bin" "$bundled_proxy/bin" >/dev/null ||
    die "bundled proxy bin directory differs from PROXY_SRC"
"$DIFF_BIN" -qr "$PROXY_SRC/src" "$bundled_proxy/src" >/dev/null ||
    die "bundled proxy src directory differs from PROXY_SRC"


if test "$bundle_signed" = yes; then
    "$CODESIGN_BIN" --verify --strict "$bundled_node" 2>/dev/null \
        || die "bundled Node is signed but its signature is not valid"
    test "$bundled_node_sha" = "$recorded_signed_node_sha" ||
        die "PROVENANCE signed Node SHA-256 does not match the bundled Node"
    signed_node_marker="CODEXMULTI_SIGNED_NODE_SHA256=$recorded_signed_node_sha"
    bundled_node_identity="signed; post-sign SHA-256 matches PROVENANCE"
else
    test "$bundled_node_sha" = "$recorded_node_sha" ||
        die "PROVENANCE unsigned Node SHA-256 does not match the bundled Node"
    "$CMP_BIN" -s "$NODE_SRC" "$bundled_node" || die "unsigned bundled Node bytes differ from NODE_SRC"
    signed_node_marker="absent (unsigned bundle)"
    bundled_node_identity="unsigned bundle bytes match NODE_SRC and PROVENANCE"
fi

strings_output="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-provenance.XXXXXX")"
cleanup() {
    /bin/rm -f -- "$strings_output"
}
trap cleanup EXIT HUP INT TERM
"$STRINGS_BIN" -a "$executable" > "$strings_output"
grep -F -x -- "$core_marker" "$strings_output" >/dev/null || die "candidate executable is missing the exact core provenance marker"
grep -F -x -- "$schema_marker" "$strings_output" >/dev/null || die "candidate executable is missing the bridge schema marker"

"$NM_BIN" -gU "$executable" | grep -Eq '[[:space:]]_cm_service_version$' || die "cm_service_version is not retained in the executable"
"$NM_BIN" -gU "$executable" | grep -Eq '[[:space:]]_cm_service_provenance$' || die "cm_service_provenance is not retained in the executable"






version_address="$("$NM_BIN" -gU "$executable" | awk '$NF == "_cm_service_version" { print $1; exit }')"
printf '%s\n' "$version_address" | grep -Eq '^[0-9a-f]{16}$' || die "cannot resolve the address of cm_service_version"
"$OTOOL_BIN" -tvV "$executable" | awk -v address="$version_address" '
    !found && !in_version && index($0, address) == 1 { in_version=1 }
    in_version && /mov[[:space:]]+w0, #0x1$/ { found=1; in_version=0 }
    in_version && /^[^[:space:]][^:]*:/ { in_version=0 }
    END { exit(found ? 0 : 1) }
' || die "cm_service_version implementation does not statically return bridge schema 1"

shell_commit="$(plist_value "$app" CodexMultiShellCommit || true)"
core_commit="$(plist_value "$app" CodexMultiCoreCommit || true)"
expected_shell_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- app)"
expected_core_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- core)"
test "$shell_commit" = "$expected_shell_commit" || die "Info.plist Swift commit does not match this checkout"
test "$core_commit" = "$expected_core_commit" || die "Info.plist core commit does not match this checkout"

printf 'CodexMulti provenance: PASS\n'
printf '  core source SHA-256: %s\n' "$core_source_sha"
printf '  core marker: %s\n' "$core_marker"
printf '  bridge marker: %s\n' "$schema_marker"
printf '  cm_service_version implementation: 1\n'
printf '  Swift commit: %s\n' "$shell_commit"
printf '  core commit: %s\n' "$core_commit"
printf '  app version marker: %s\n' "$app_version_marker"
printf '  build number marker: %s\n' "$build_number_marker"
printf '  proxy marker: %s\n' "$proxy_marker"
printf '  proxy tree marker: %s\n' "$proxy_tree_marker"
printf '  Node version marker: %s\n' "$node_version_marker"
printf '  Node SHA-256 marker: %s\n' "$node_sha_marker"
printf '  signed Node SHA-256 marker: %s\n' "$signed_node_marker"
printf '  proxy tree digest: recomputed and matched\n'
printf '  proxy tree: package.json, bin/, and src/ match %s\n' "$PROXY_SRC"
printf '  bundled Node: %s\n' "$bundled_node_identity"
printf '  bundled Node license: non-empty and matches %s\n' "$node_license_src"

maintenance="$app/Contents/Helpers/codexmulti-maintenance"
test -f "$maintenance" && test -x "$maintenance" && test ! -L "$maintenance" || die "maintenance helper is missing or unsafe"
"$STRINGS_BIN" -a "$maintenance" | grep -F -x -- "$core_marker" >/dev/null || die "maintenance source provenance mismatch"
printf '  maintenance helper: executable with matching core source provenance\n'

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
CORE_DIR="${CODEXMULTI_CORE_DIR:-$REPO_ROOT/core}"
CORE_DIR="$(cd "$CORE_DIR" && pwd -P)"
PROXY_SRC="${PROXY_SRC:-$REPO_ROOT/proxy}"
NODE_SRC="${NODE_SRC:-$PROJECT_DIR/.node/v26.8.1/bin/node}"
CORE_OBJECT="$CORE_DIR/zig-out/lib/cmcore.o"
LOCAL_CORE_OBJECT="$PROJECT_DIR/zig/zig-out/lib/cmcore.o"
INFO_TEMPLATE="$PROJECT_DIR/Resources/Info.plist"
ICON_BUILDER="$SCRIPT_DIR/make-icon.sh"
ICON_OUTPUT="$PROJECT_DIR/Resources/AppIcon.icns"
TRAY_ICON_BUILDER="$SCRIPT_DIR/make-tray-icon.sh"
BUNDLE_OUTPUT="$PROJECT_DIR/dist/staging/CodexMulti.app"
ZIG="${ZIG:-zig}"
SWIFT="${SWIFT:-/usr/bin/swift}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
STRINGS_BIN="${STRINGS_BIN:-/usr/bin/strings}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"
STAT_BIN="${STAT_BIN:-/usr/bin/stat}"
. "$SCRIPT_DIR/build-metadata.sh"

PROXY_COMMIT=""
NODE_VERSION=""
NODE_LICENSE_SRC=""
CORE_SOURCE_MARKER=""
APP_VERSION=""
BUILD_NUMBER=""

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_tool() {
    case "$1" in
        */*) test -x "$1" ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac || die "required tool is unavailable: $1"
}

proxy_tree_sha256() {
    local proxy_root manifest_path status digest
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

replace_optional_plist_value() {
    local plist key value
    plist="$1"
    key="$2"
    value="$3"
    if "$PLUTIL_BIN" -extract "$key" raw -o - "$plist" >/dev/null 2>&1; then
        "$PLUTIL_BIN" -replace "$key" -string "$value" "$plist"
    fi
}

resolve_bundle_inputs() {
    local proxy_root proxy_relative node_root
    test -d "$PROXY_SRC" || die "proxy source directory is missing: $PROXY_SRC"
    PROXY_SRC="$(cd "$PROXY_SRC" && pwd -P)"
    case "$PROXY_SRC" in
        "$REPO_ROOT"/*) ;;
        *) die "PROXY_SRC must be inside the monorepo: $PROXY_SRC" ;;
    esac
    proxy_root="$(git -C "$PROXY_SRC" rev-parse --show-toplevel 2>/dev/null || true)"
    test "$proxy_root" = "$REPO_ROOT" ||
        die "PROXY_SRC must belong to the monorepo checkout: $PROXY_SRC"
    proxy_relative="${PROXY_SRC#"$REPO_ROOT"/}"
    test -f "$PROXY_SRC/package.json" || die "proxy package.json is missing: $PROXY_SRC/package.json"
    test -d "$PROXY_SRC/bin" || die "proxy bin directory is missing: $PROXY_SRC/bin"
    test -d "$PROXY_SRC/src" || die "proxy src directory is missing: $PROXY_SRC/src"
    test -x "$PROXY_SRC/bin/codexmulti-proxy" ||
        die "proxy entrypoint is missing or not executable: $PROXY_SRC/bin/codexmulti-proxy"
    PROXY_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$proxy_relative")"
    printf '%s\n' "$PROXY_COMMIT" | grep -Eq '^[0-9a-f]{40}$' ||
        die "could not resolve the proxy commit"

    test -f "$NODE_SRC" || die "Node source is missing or not a regular file target: $NODE_SRC"
    test -x "$NODE_SRC" || die "Node source is not executable: $NODE_SRC"
    NODE_VERSION="$("$NODE_SRC" --version)"
    printf '%s\n' "$NODE_VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+' ||
        die "Node source returned an invalid version: $NODE_VERSION"
    node_root="$(cd "$(dirname "$NODE_SRC")/.." && pwd -P)"
    test "${node_root##*/}" = "$NODE_VERSION" ||
        die "Node source must be stored under its version directory $NODE_VERSION: $NODE_SRC"
    NODE_LICENSE_SRC="$node_root/LICENSE"
    test -s "$NODE_LICENSE_SRC" || die "Node license is missing or empty for $NODE_VERSION: $NODE_LICENSE_SRC"
    test ! -L "$NODE_LICENSE_SRC" || die "Node license must not be a symlink: $NODE_LICENSE_SRC"
}

core_source_sha256() {
    local list_path source_path
    list_path="$CORE_DIR/scripts/core-source-list.txt"
    test -s "$list_path" || die "core source list is missing or empty: $list_path"
    while IFS= read -r source_path; do
        test -n "$source_path" || continue
        case "$source_path" in
            /*|*../*) die "unsafe core source-list entry: $source_path" ;;
        esac
        test -f "$CORE_DIR/$source_path" || die "listed core source is missing: $source_path"
    done < "$list_path"
    (cd "$CORE_DIR" && xargs "$SHASUM_BIN" -a 256 < "$list_path" | "$SHASUM_BIN" -a 256 | awk '{print $1}')
}

require_core_marker() {
    local object marker
    object="$1"
    marker="$2"
    "$STRINGS_BIN" -a "$object" | grep -F -x -- "$marker" >/dev/null ||
        die "core object does not contain expected provenance marker: $object"
}

build_core() {
    local source_sha expected_marker build_status
    source_sha="$(core_source_sha256)"
    printf '%s\n' "$source_sha" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate the core source SHA-256"
    expected_marker="CODEXMULTI_CORE_SRC_SHA256=$source_sha"
    CORE_SOURCE_MARKER="$expected_marker"

    build_status=0
    (
        cd "$CORE_DIR"
        ZIG_LOCAL_CACHE_DIR="$CORE_DIR/.zig-cache" \
        ZIG_GLOBAL_CACHE_DIR="$CORE_DIR/.zig-cache/global" \
        "$ZIG" build cmcore -Doptimize=ReleaseSafe -Dtarget=aarch64-macos \
            -Dcore-provenance="$expected_marker" --summary all
    ) || build_status=$?

    if test "$build_status" -ne 0; then
        printf 'warning: zig build cmcore failed with status %s; checking the prebuilt object\n' "$build_status" >&2
        test -f "$CORE_OBJECT" || die "zig build failed and no prebuilt core object exists"
        require_core_marker "$CORE_OBJECT" "$expected_marker"
        printf 'core object source: validated prebuilt fallback %s\n' "$CORE_OBJECT"
    else
        test -f "$CORE_OBJECT" || die "zig build succeeded but did not emit $CORE_OBJECT"
        require_core_marker "$CORE_OBJECT" "$expected_marker"
        printf 'core object source: fresh Zig ReleaseSafe aarch64-macos build\n'
    fi

    mkdir -p "$(dirname "$LOCAL_CORE_OBJECT")"
    /bin/cp -f "$CORE_OBJECT" "$LOCAL_CORE_OBJECT"
    /bin/cp -f "$CORE_DIR/include/cmcore.h" "$PROJECT_DIR/Sources/CMCore/cmcore.h"
    /usr/bin/cmp -s "$CORE_DIR/include/cmcore.h" "$PROJECT_DIR/Sources/CMCore/cmcore.h" ||
        die "copied C bridge header differs from Lane C"
    printf 'core source SHA-256: %s\n' "$source_sha"
}

assemble_bundle() {
    local shell_commit core_commit swift_bin_path executable temp_root temp_bundle proxy_output
    local proxy_tree_sha node_sha
    local -a swift_build_args
    shell_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- app)"
    core_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- core)"
    swift_build_args=(--package-path "$PROJECT_DIR" -c release --product CodexMulti)
    if test "${CODEXMULTI_SWIFT_DISABLE_SANDBOX:-no}" = yes; then
        swift_build_args=(--disable-sandbox "${swift_build_args[@]}")
    fi
    "$SWIFT" build "${swift_build_args[@]}"
    swift_bin_path="$("$SWIFT" build "${swift_build_args[@]}" --show-bin-path)"
    executable="$swift_bin_path/CodexMulti"
    test -x "$executable" || die "Swift build did not emit an executable: $executable"







    test -n "$CORE_SOURCE_MARKER" || die "core provenance marker was not computed"
    if ! "$STRINGS_BIN" -a "$executable" | grep -F -x -- "$CORE_SOURCE_MARKER" >/dev/null; then
        printf 'relinking: the linked executable carried a stale core provenance marker\n' >&2
        /bin/rm -f "$executable"
        "$SWIFT" build "${swift_build_args[@]}"
        test -x "$executable" || die "Swift relink did not emit an executable: $executable"
        "$STRINGS_BIN" -a "$executable" | grep -F -x -- "$CORE_SOURCE_MARKER" >/dev/null ||
            die "the linked executable does not carry the current core provenance marker"
    fi

    temp_root="$(mktemp -d "$PROJECT_DIR/dist/staging/.CodexMulti.bundle.XXXXXX")"
    temp_bundle="$temp_root/CodexMulti.app"
    cleanup_bundle() {
        case "$temp_root" in
            "$PROJECT_DIR"/dist/staging/.CodexMulti.bundle.*) /bin/rm -rf -- "$temp_root" ;;
        esac
    }
    trap cleanup_bundle RETURN
    proxy_output="$temp_bundle/Contents/Resources/proxy"
    mkdir -p "$temp_bundle/Contents/MacOS" "$temp_bundle/Contents/Helpers" \
        "$temp_bundle/Contents/Resources/Licenses" "$proxy_output"
    /bin/cp -f "$executable" "$temp_bundle/Contents/MacOS/CodexMulti"

    /bin/cp -fL "$NODE_SRC" "$temp_bundle/Contents/Helpers/node"
    /bin/cp -f "$NODE_LICENSE_SRC" "$temp_bundle/Contents/Resources/Licenses/Node.LICENSE"
    chmod 0755 "$temp_bundle/Contents/Helpers/node"
    test ! -L "$temp_bundle/Contents/Helpers/node" || die "bundled Node runtime must not be a symlink"
    test -s "$temp_bundle/Contents/Resources/Licenses/Node.LICENSE" || die "bundled Node license is missing or empty"
    "$DITTO_BIN" "$PROXY_SRC/bin" "$proxy_output/bin"
    "$DITTO_BIN" "$PROXY_SRC/src" "$proxy_output/src"
    /bin/cp -f "$PROXY_SRC/package.json" "$proxy_output/package.json"
    proxy_tree_sha="$(proxy_tree_sha256 "$proxy_output")"
    node_sha="$("$SHASUM_BIN" -a 256 "$temp_bundle/Contents/Helpers/node" | awk '{print $1}')"
    printf '%s\n' "$proxy_tree_sha" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate the bundled proxy tree SHA-256"
    printf '%s\n' "$node_sha" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate the unsigned bundled Node SHA-256"
    printf 'CODEXMULTI_APP_VERSION=%s\nCODEXMULTI_BUILD_NUMBER=%s\nCODEXMULTI_PROXY_COMMIT=%s\nCODEXMULTI_PROXY_TREE_SHA256=%s\nCODEXMULTI_NODE_VERSION=%s\nCODEXMULTI_NODE_SHA256=%s\n' \
        "$APP_VERSION" "$BUILD_NUMBER" "$PROXY_COMMIT" "$proxy_tree_sha" "$NODE_VERSION" "$node_sha" > "$proxy_output/PROVENANCE"
    /bin/cp -f "$INFO_TEMPLATE" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CFBundleShortVersionString -string "$APP_VERSION" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CFBundleVersion -string "$BUILD_NUMBER" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CodexMultiShellCommit -string "$shell_commit" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CodexMultiCoreCommit -string "$core_commit" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CodexMultiProxyCommit -string "$PROXY_COMMIT" "$temp_bundle/Contents/Info.plist"
    "$PLUTIL_BIN" -replace CodexMultiNodeVersion -string "$NODE_VERSION" "$temp_bundle/Contents/Info.plist"
    replace_optional_plist_value "$temp_bundle/Contents/Info.plist" CodexMultiProxyTreeSHA256 "$proxy_tree_sha"
    replace_optional_plist_value "$temp_bundle/Contents/Info.plist" CodexMultiNodeSHA256 "$node_sha"
    /bin/cp -f "$ICON_OUTPUT" "$temp_bundle/Contents/Resources/AppIcon.icns"
    for tray_icon in TrayIcon.png TrayIcon@2x.png TrayIcon@3x.png; do
        test -s "$PROJECT_DIR/Resources/$tray_icon" || die "tray icon is missing or empty: $tray_icon"
        /bin/cp -f "$PROJECT_DIR/Resources/$tray_icon" "$temp_bundle/Contents/Resources/$tray_icon"
    done
    printf 'APPL????' > "$temp_bundle/Contents/PkgInfo"

    if test -e "$BUNDLE_OUTPUT"; then
        /bin/rm -rf -- "$BUNDLE_OUTPUT"
    fi
    mv "$temp_bundle" "$BUNDLE_OUTPUT"
    cleanup_bundle
    trap - RETURN

    printf 'CodexMulti unsigned bundle: %s\n' "$BUNDLE_OUTPUT"
    printf '  executable SHA-256: %s\n' "$("$SHASUM_BIN" -a 256 "$BUNDLE_OUTPUT/Contents/MacOS/CodexMulti" | awk '{print $1}')"
    printf '  Node SHA-256: %s\n' "$("$SHASUM_BIN" -a 256 "$BUNDLE_OUTPUT/Contents/Helpers/node" | awk '{print $1}')"
    printf '  proxy commit: %s\n' "$PROXY_COMMIT"
    printf '  proxy tree SHA-256: %s\n' "$proxy_tree_sha"
    printf '  Node version: %s\n' "$NODE_VERSION"
    printf '  app version: %s\n' "$APP_VERSION"
    printf '  build number: %s\n' "$BUILD_NUMBER"
    printf '  retained provenance markers:\n'
    require_executable_markers "$BUNDLE_OUTPUT/Contents/MacOS/CodexMulti"
    printf 'No bundle was signed, installed, or launched.\n'
}




require_executable_markers() {
    local executable markers prefix
    executable="$1"
    markers="$("$STRINGS_BIN" -a "$executable" |
        grep -E '^CODEXMULTI_(CORE_SRC_SHA256|BRIDGE_SCHEMA)=' | sort -u || true)"
    for prefix in CODEXMULTI_CORE_SRC_SHA256= CODEXMULTI_BRIDGE_SCHEMA=; do
        printf '%s\n' "$markers" | grep -F -- "$prefix" >/dev/null ||
            die "linked executable does not retain the ${prefix%=} provenance marker: $executable"
    done
    printf '%s\n' "$markers" | sed 's/^/    /'
}

require_tool "$ZIG"
require_tool "$SWIFT"
require_tool "$SHASUM_BIN"
require_tool "$STRINGS_BIN"
require_tool "$PLUTIL_BIN"
require_tool "$ICON_BUILDER"
require_tool "$TRAY_ICON_BUILDER"
require_tool "$DITTO_BIN"
require_tool "$STAT_BIN"
test -f "$INFO_TEMPLATE" || die "Info.plist template is missing: $INFO_TEMPLATE"

resolve_build_metadata
resolve_bundle_inputs
mkdir -p "$PROJECT_DIR/dist/staging"
build_core
"$ICON_BUILDER"
"$TRAY_ICON_BUILDER"
assemble_bundle

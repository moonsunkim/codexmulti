#!/bin/bash

set -euo pipefail

IDENTITY_NAME="CodexMulti Local Code Signing"
BUNDLE_ID="dev.codexmulti.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
CORE_DIR="${CODEXMULTI_CORE_DIR:-$REPO_ROOT/core}"
CORE_DIR="$(cd "$CORE_DIR" && pwd -P)"
STATE_DIR="${CODEXMULTI_SIGNING_STATE_DIR:-$CORE_DIR/.local-signing}"
FINGERPRINT_FILE="$STATE_DIR/identity.sha1"
REQUIREMENT_FILE="$STATE_DIR/designated-requirement.txt"
TARGET_APP="$PROJECT_DIR/dist/CodexMulti.app"
UNSIGNED_APP="$PROJECT_DIR/dist/staging/CodexMulti.app"
SECURITY_BIN="${SECURITY_BIN:-/usr/bin/security}"
CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
PLUTIL_BIN="${PLUTIL_BIN:-/usr/bin/plutil}"
IDENTITY_AUDIT_BIN="${IDENTITY_AUDIT_BIN:-$CORE_DIR/scripts/codexmulti-signing-identity.sh}"
BUILD_APP_BIN="${BUILD_APP_BIN:-$SCRIPT_DIR/build-app.sh}"
PROVENANCE_AUDIT_BIN="${PROVENANCE_AUDIT_BIN:-$SCRIPT_DIR/verify-provenance.sh}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
NODE_ENTITLEMENTS="$PROJECT_DIR/Resources/node.entitlements"
NESTED_NODE_RELATIVE="Contents/Helpers/node"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/package-signed-macos.sh [--audit|--dry-run]
  scripts/package-signed-macos.sh --stage /private/tmp/<candidate>.app
  scripts/package-signed-macos.sh --package

Audit is read-only and is the default. --dry-run validates the unsigned nested
layout and prints the inside-out signing plan without reading the Keychain.
--stage builds and signs a new bundle at the requested /private/tmp path.
--package replaces only dist/CodexMulti.app,
with a timestamped dist backup and rollback on failed final verification.

--initialize-requirement is always refused. This shell must reproduce the
already accepted designated requirement byte-for-byte.
EOF
}

require_tool() {
    test -x "$1" || die "required tool is unavailable: $1"
}

validate_node_entitlements() {
    local entitlements key_count
    entitlements="$1"
    test -f "$entitlements" || die "Node entitlements are missing: $entitlements"
    "$PLUTIL_BIN" -lint "$entitlements" >/dev/null || die "Node entitlements are not a valid plist: $entitlements"
    test "$("$PLUTIL_BIN" -extract 'com\.apple\.security\.cs\.allow-jit' raw -o - "$entitlements" 2>/dev/null || true)" = true ||
        die "Node entitlements do not enable com.apple.security.cs.allow-jit"
    test "$("$PLUTIL_BIN" -extract 'com\.apple\.security\.cs\.allow-unsigned-executable-memory' raw -o - "$entitlements" 2>/dev/null || true)" = true ||
        die "Node entitlements do not enable com.apple.security.cs.allow-unsigned-executable-memory"
    test -z "$("$PLUTIL_BIN" -extract 'com\.apple\.security\.cs\.disable-library-validation' raw -o - "$entitlements" 2>/dev/null || true)" ||
        die "Node entitlements unexpectedly disable library validation"
    key_count="$("$PLUTIL_BIN" -convert xml1 -o - "$entitlements" | grep -c '<key>' | tr -d '[:space:]')"
    test "$key_count" = "2" || die "Node entitlements contain unexpected keys"
}

require_unsigned_nested_layout() {
    local app
    app="$1"
    test -d "$app" || die "unsigned candidate app does not exist: $app"
    test -x "$app/$NESTED_NODE_RELATIVE" || die "unsigned candidate is missing bundled Node: $app/$NESTED_NODE_RELATIVE"
    test ! -L "$app/$NESTED_NODE_RELATIVE" || die "bundled Node must not be a symlink"
    test -f "$app/Contents/Resources/proxy/package.json" || die "unsigned candidate is missing proxy package.json"
    test -x "$app/Contents/Resources/proxy/bin/codexmulti-proxy" || die "unsigned candidate is missing the proxy entrypoint"
    test -f "$app/Contents/Resources/proxy/src/server.mjs" || die "unsigned candidate is missing proxy src/server.mjs"
    test -f "$app/Contents/Resources/proxy/PROVENANCE" || die "unsigned candidate is missing proxy provenance"
}

canonical_stage_output() {
    local requested relative leaf lexical_parent relative_parent component current
    local physical_tmp physical_parent
    local -a components
    requested="$1"

    case "$requested" in
        /private/tmp/*.app) ;;
        *) die "--stage output must be an absolute /private/tmp/*.app path: $requested" ;;
    esac
    case "$requested" in
        *//* ) die "--stage output contains an empty path component: $requested" ;;
    esac
    relative="${requested#/private/tmp/}"
    case "/$relative/" in
        *"/./"*|*"/../"*) die "--stage output contains a dot path component: $requested" ;;
    esac

    leaf="${requested##*/}"
    test -n "$leaf" || die "--stage output has an empty final component"
    lexical_parent="${requested%/*}"
    test -d "$lexical_parent" ||
        die "--stage parent must already exist so it can be verified before output creation: $lexical_parent"



    current="/private/tmp"
    test ! -L "$current" || die "physical staging root must not be a symlink: $current"
    relative_parent="${lexical_parent#/private/tmp}"
    relative_parent="${relative_parent#/}"
    if test -n "$relative_parent"; then
        IFS='/' read -r -a components <<< "$relative_parent"
        for component in "${components[@]}"; do
            test -n "$component" || die "--stage parent contains an empty path component"
            current="$current/$component"
            test ! -L "$current" || die "--stage parent traverses a symlink: $current"
            test -d "$current" || die "--stage parent component is not a directory: $current"
        done
    fi

    physical_tmp="$(cd /private/tmp && pwd -P)" || die "cannot resolve physical /private/tmp"
    physical_parent="$(cd "$lexical_parent" && pwd -P)" ||
        die "cannot resolve physical --stage parent: $lexical_parent"
    case "$physical_parent" in
        "$physical_tmp"|"$physical_tmp"/*) ;;
        *) die "--stage parent escapes physical /private/tmp: $physical_parent" ;;
    esac

    requested="$physical_parent/$leaf"
    test ! -e "$requested" || die "--stage output already exists: $requested"
    test ! -L "$requested" || die "--stage output is a symlink: $requested"
    printf '%s\n' "$requested"
}

login_keychain() {
    local output path
    output="$($SECURITY_BIN login-keychain 2>&1)" || die "cannot resolve the user login Keychain: $output"
    path="$(printf '%s\n' "$output" | sed -nE 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/p' | sed -n '1p')"
    test -n "$path" || die "security login-keychain returned an unrecognized value: $output"
    printf '%s\n' "$path"
}

read_pinned_hash() {
    local value
    test -f "$FINGERPRINT_FILE" || die "missing signing identity pin: $FINGERPRINT_FILE"
    value="$(tr -d '[:space:]' < "$FINGERPRINT_FILE" | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "$value" | grep -Eq '^[0-9A-F]{40}$' || die "invalid SHA-1 identity pin in $FINGERPRINT_FILE"
    printf '%s\n' "$value"
}

resolve_identity() {
    local keychain expected output hashes count search_output search_count
    if ! "$IDENTITY_AUDIT_BIN" audit >/dev/null; then
        die "signing identity audit failed"
    fi
    keychain="$(login_keychain)"
    expected="$(read_pinned_hash)"
    output="$($SECURITY_BIN find-identity -v -p codesigning "$keychain" 2>&1 || true)"
    hashes="$(printf '%s\n' "$output" |
        sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-Fa-f]{40}) "CodexMulti Local Code Signing"[[:space:]]*$/\1/p' |
        tr '[:lower:]' '[:upper:]')"
    count="$(printf '%s\n' "$hashes" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    test "$count" = "1" || die "expected exactly one valid '$IDENTITY_NAME' identity in the login Keychain; found $count"
    test "$hashes" = "$expected" || die "the valid identity does not match the machine-local pin"

    search_output="$($SECURITY_BIN find-identity -v -p codesigning 2>&1 || true)"
    search_count="$(printf '%s\n' "$search_output" |
        sed -nE "s/^[[:space:]]*[0-9]+\) ($expected) .*$/\1/p" |
        wc -l | tr -d '[:space:]')"
    test "$search_count" = "1" || die "the pinned identity must occur exactly once in the default Keychain search list; found $search_count"
    printf '%s\n' "$expected"
}

designated_requirement() {
    local app output requirement
    app="$1"
    output="$($CODESIGN_BIN -d -r- "$app" 2>&1)" || return 1
    requirement="$(printf '%s\n' "$output" |
        sed -nE 's/^[[:space:]]*#?[[:space:]]*designated =>[[:space:]]*//p' |
        sed -n '1p')"
    test -n "$requirement" || return 1
    printf '%s\n' "$requirement"
}

bundle_id() {
    "$PLUTIL_BIN" -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null
}

validate_requirement_shape() {
    local requirement identity_hash lower_requirement lower_hash
    requirement="$1"
    identity_hash="$2"
    case "$requirement" in
        *cdhash*) die "refusing exact-CDHash designated requirement: $requirement" ;;
    esac
    case "$requirement" in
        *"identifier \"$BUNDLE_ID\""*) ;;
        *) die "designated requirement does not preserve bundle identifier $BUNDLE_ID: $requirement" ;;
    esac
    lower_requirement="$(printf '%s' "$requirement" | tr '[:upper:]' '[:lower:]')"
    lower_hash="$(printf '%s' "$identity_hash" | tr '[:upper:]' '[:lower:]')"
    case "$lower_requirement" in
        *"$lower_hash"*) ;;
        *) die "designated requirement is not bound to the pinned signing certificate: $requirement" ;;
    esac
}

read_pinned_requirement() {
    local value
    test -f "$REQUIREMENT_FILE" || die "missing pinned designated requirement: $REQUIREMENT_FILE"
    value="$(sed -n '1p' "$REQUIREMENT_FILE")"
    test -n "$value" || die "pinned designated requirement is empty"
    printf '%s\n' "$value"
}

require_hardened_runtime() {
    local details expected_identifier
    expected_identifier="${2:-}"
    details="$($CODESIGN_BIN -d --verbose=4 "$1" 2>&1)" || die "cannot inspect signed bundle details: $1"
    if test -n "$expected_identifier"; then
        printf '%s\n' "$details" | grep -F "Identifier=$expected_identifier" >/dev/null ||
            die "signed identifier is missing or changed"
    fi
    printf '%s\n' "$details" | grep -E 'flags=0x[0-9a-fA-F]*10000.*\(runtime\)' >/dev/null ||
        die "hardened-runtime flag is missing: $1"
}

verify_signed_node() {
    local app node extracted_entitlements
    app="$1"
    node="$app/$NESTED_NODE_RELATIVE"
    test -x "$node" || die "signed bundle is missing nested Node: $node"
    test ! -L "$node" || die "nested Node must not be a symlink"
    "$CODESIGN_BIN" --verify --strict --verbose=2 "$node" || die "nested Node signature verification failed"
    require_hardened_runtime "$node"
    extracted_entitlements="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-node-entitlements.XXXXXX")"
    "$CODESIGN_BIN" -d --entitlements :- "$node" > "$extracted_entitlements" 2>/dev/null ||
        die "cannot extract nested Node entitlements"
    validate_node_entitlements "$extracted_entitlements"
    /bin/rm -f -- "$extracted_entitlements"
}

verify_signed_app() {
    local app identity_hash pinned_requirement require_clean actual_id actual_requirement
    app="$1"
    identity_hash="$2"
    pinned_requirement="$3"
    require_clean="${4:-no}"
    actual_id="$(bundle_id "$app" || true)"
    test "$actual_id" = "$BUNDLE_ID" || die "bundle id changed: expected $BUNDLE_ID, got ${actual_id:-unreadable}"
    if ! "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$app"; then
        die "strict code-sign verification failed: $app"
    fi
    actual_requirement="$(designated_requirement "$app")" || die "cannot read the signed designated requirement"
    validate_requirement_shape "$actual_requirement" "$identity_hash"
    test "$actual_requirement" = "$pinned_requirement" ||
        die "designated requirement drifted; pinned='$pinned_requirement' new='$actual_requirement'"
    require_hardened_runtime "$app" "$BUNDLE_ID"
    verify_signed_node "$app"
    if test "$require_clean" = yes; then
        if ! "$PROVENANCE_AUDIT_BIN" --require-clean "$app"; then
            die "clean-checkout provenance verification failed: $app"
        fi
    elif ! "$PROVENANCE_AUDIT_BIN" "$app"; then
        die "provenance verification failed: $app"
    fi
}

record_signed_node_sha256() {
    local app node provenance signed_node_sha temporary marker
    app="$1"
    node="$app/$NESTED_NODE_RELATIVE"
    provenance="$app/Contents/Resources/proxy/PROVENANCE"
    test -f "$provenance" || die "signed candidate is missing proxy provenance: $provenance"
    signed_node_sha="$("$SHASUM_BIN" -a 256 "$node" | awk '{print $1}')"
    printf '%s\n' "$signed_node_sha" | grep -Eq '^[0-9a-f]{64}$' ||
        die "could not calculate the signed bundled Node SHA-256"
    marker="CODEXMULTI_SIGNED_NODE_SHA256=$signed_node_sha"
    temporary="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-signed-node-provenance.XXXXXX")"
    awk -v marker="$marker" '
        BEGIN { written = 0 }
        /^CODEXMULTI_SIGNED_NODE_SHA256=/ {
            if (!written) print marker
            written = 1
            next
        }
        { print }
        END { if (!written) print marker }
    ' "$provenance" > "$temporary" || {
        /bin/rm -f -- "$temporary"
        die "could not update signed Node provenance"
    }
    /bin/cp -f "$temporary" "$provenance"
    /bin/rm -f -- "$temporary"
    if "$PLUTIL_BIN" -extract CodexMultiSignedNodeSHA256 raw -o - "$app/Contents/Info.plist" >/dev/null 2>&1; then
        "$PLUTIL_BIN" -replace CodexMultiSignedNodeSHA256 -string "$signed_node_sha" "$app/Contents/Info.plist"
    fi
}

build_and_sign() {
    local output identity_hash pinned_requirement require_clean validate_stage_path
    output="$1"
    identity_hash="$2"
    pinned_requirement="$3"
    require_clean="${4:-no}"
    validate_stage_path="${5:-no}"
    test ! -e "$output" || die "signing staging path already exists: $output"

    "$BUILD_APP_BIN"
    test -d "$UNSIGNED_APP" || die "build script did not produce $UNSIGNED_APP"
    if test "$validate_stage_path" = yes; then
        output="$(canonical_stage_output "$output")"
    fi
    /usr/bin/ditto "$UNSIGNED_APP" "$output"
    require_unsigned_nested_layout "$output"
    validate_node_entitlements "$NODE_ENTITLEMENTS"
    "$CODESIGN_BIN" --force --sign "$identity_hash" --options runtime --timestamp=none \
        --entitlements "$NODE_ENTITLEMENTS" "$output/$NESTED_NODE_RELATIVE"
    record_signed_node_sha256 "$output"
    "$CODESIGN_BIN" --force --sign "$identity_hash" --options runtime --timestamp=none \
        --identifier "$BUNDLE_ID" "$output"
    verify_signed_app "$output" "$identity_hash" "$pinned_requirement" "$require_clean"
}

audit() {
    local identity_hash pinned_requirement current_id current_requirement
    identity_hash="$(resolve_identity)"
    pinned_requirement="$(read_pinned_requirement)"
    validate_requirement_shape "$pinned_requirement" "$identity_hash"

    printf 'CodexMulti Swift signed-package audit: identity ready\n'
    printf '  identity: %s\n' "$IDENTITY_NAME"
    printf '  pinned SHA-1: %s\n' "$identity_hash"
    printf '  target bundle id: %s\n' "$BUNDLE_ID"
    printf '  signing state: %s\n' "$STATE_DIR"
    printf '  pinned designated requirement: %s\n' "$pinned_requirement"
    printf '  package target: %s\n' "$TARGET_APP"

    if test -d "$TARGET_APP"; then
        current_id="$(bundle_id "$TARGET_APP" || true)"
        current_requirement="$(designated_requirement "$TARGET_APP" || true)"
        printf '  existing bundle id: %s\n' "${current_id:-unreadable}"
        printf '  existing designated requirement: %s\n' "${current_requirement:-unreadable}"
        if "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$TARGET_APP" >/dev/null 2>&1; then
            printf '  existing strict signature: valid\n'
        else
            die "existing strict signature is invalid: $TARGET_APP"
        fi
        require_hardened_runtime "$TARGET_APP" "$BUNDLE_ID"
        verify_signed_node "$TARGET_APP"
        printf '  existing nested Node signature: valid\n'
        printf '  existing nested Node hardened runtime: present\n'
        printf '  existing nested Node entitlements: exact expected pair\n'
    else
        printf '  existing package target: absent; no backup would be created on the next --package\n'
    fi

    printf '  rollback ladder: sign+verify temporary bundle; move existing target to dist/CodexMulti.app.backup.<UTC>; move candidate into place; restore backup on any final verification failure\n'
    printf '  audit: no build, signing, bundle replacement, Keychain mutation, install, or launch occurred\n'
}

dry_run() {
    validate_node_entitlements "$NODE_ENTITLEMENTS"
    if test -d "$UNSIGNED_APP"; then
        require_unsigned_nested_layout "$UNSIGNED_APP"
        "$PROVENANCE_AUDIT_BIN" "$UNSIGNED_APP"
        printf 'CodexMulti inside-out signing dry run: unsigned bundle validated\n'
    else
        printf 'CodexMulti inside-out signing dry run: unsigned bundle absent; command plan only\n'
    fi
    printf '  1. codesign --force --sign <pinned-sha1> --options runtime --timestamp=none --entitlements %s <candidate.app>/%s\n' \
        "$NODE_ENTITLEMENTS" "$NESTED_NODE_RELATIVE"
    printf '  2. hash the signed Node and upsert CODEXMULTI_SIGNED_NODE_SHA256 in PROVENANCE (and Info.plist when its key exists)\n'
    printf '  3. codesign --force --sign <pinned-sha1> --options runtime --timestamp=none --identifier %s <candidate.app>\n' "$BUNDLE_ID"
    printf '  4. verify nested Node signature, hardened runtime, and exact entitlements\n'
    printf '  5. verify app strict signature, hardened runtime, designated-requirement pin, and provenance\n'
    printf 'No Keychain read, build, signing, bundle replacement, install, or launch occurred.\n'
}

stage_app() {
    local requested_output output identity_hash pinned_requirement
    requested_output="$1"
    output="$(canonical_stage_output "$requested_output")"
    identity_hash="$(resolve_identity)"
    pinned_requirement="$(read_pinned_requirement)"
    validate_requirement_shape "$pinned_requirement" "$identity_hash"

    cleanup_stage() {
        if test -e "$output" && test "${stage_complete:-no}" != yes; then
            case "$output" in
                /private/tmp/*.app) /bin/rm -rf -- "$output" ;;
            esac
        fi
    }
    stage_complete=no
    trap cleanup_stage EXIT HUP INT TERM
    build_and_sign "$output" "$identity_hash" "$pinned_requirement" no yes
    stage_complete=yes
    trap - EXIT HUP INT TERM

    printf 'CodexMulti fresh signed staging bundle: %s\n' "$output"
    printf '  executable SHA-256: %s\n' "$("$SHASUM_BIN" -a 256 "$output/Contents/MacOS/CodexMulti" | awk '{print $1}')"
    printf '  signing identity SHA-1: %s\n' "$identity_hash"
    printf '  designated requirement: %s\n' "$(designated_requirement "$output")"
    printf '  strict signature: valid\n'
    printf '  hardened runtime: present\n'
    printf '  nested Node signature: valid\n'
    printf '  nested Node hardened runtime: present\n'
    printf '  nested Node entitlements: exact expected pair\n'
    printf 'No project dist package or /Applications app was changed or launched.\n'
}

package_app() {
    local identity_hash pinned_requirement dist_dir staging_app backup_app stamp install_started install_committed
    identity_hash="$(resolve_identity)"
    pinned_requirement="$(read_pinned_requirement)"
    validate_requirement_shape "$pinned_requirement" "$identity_hash"
    dist_dir="$PROJECT_DIR/dist"
    mkdir -p "$dist_dir"
    staging_app="$dist_dir/.CodexMulti.app.staging.$$"
    test ! -e "$staging_app" || die "staging path already exists: $staging_app"
    backup_app=""
    install_started=no
    install_committed=no

    cleanup_package() {
        if test "$install_started" = yes && test "$install_committed" != yes; then
            if test -e "$TARGET_APP" && test ! -e "$staging_app"; then
                mv "$TARGET_APP" "$staging_app" || true
            fi
            if test -n "$backup_app" && test -e "$backup_app" && test ! -e "$TARGET_APP"; then
                mv "$backup_app" "$TARGET_APP" || true
            fi
        fi
        if test -e "$staging_app"; then
            case "$staging_app" in
                "$dist_dir"/.CodexMulti.app.staging.*) /bin/rm -rf -- "$staging_app" ;;
            esac
        fi
    }
    trap cleanup_package EXIT
    trap 'cleanup_package; exit 1' HUP INT TERM

    build_and_sign "$staging_app" "$identity_hash" "$pinned_requirement" yes
    install_started=yes
    if test -e "$TARGET_APP"; then
        stamp="$(date -u '+%Y%m%dT%H%M%SZ')"
        backup_app="$dist_dir/CodexMulti.app.backup.$stamp"
        test ! -e "$backup_app" || die "backup path already exists: $backup_app"
        mv "$TARGET_APP" "$backup_app"
    fi
    if ! mv "$staging_app" "$TARGET_APP"; then
        if test -n "$backup_app" && test -e "$backup_app"; then
            mv "$backup_app" "$TARGET_APP" || true
        fi
        die "could not move the verified staging bundle into dist"
    fi

    verify_signed_app "$TARGET_APP" "$identity_hash" "$pinned_requirement" yes || {
        if test -e "$TARGET_APP" && test ! -e "$staging_app"; then
            mv "$TARGET_APP" "$staging_app" || true
        fi
        if test -n "$backup_app" && test -e "$backup_app" && test ! -e "$TARGET_APP"; then
            mv "$backup_app" "$TARGET_APP" || true
        fi
        die "final package verification failed; the previous dist bundle was restored when present"
    }

    install_committed=yes
    trap - EXIT HUP INT TERM
    printf 'CodexMulti signed package installed project-locally: %s\n' "$TARGET_APP"
    printf '  executable SHA-256: %s\n' "$("$SHASUM_BIN" -a 256 "$TARGET_APP/Contents/MacOS/CodexMulti" | awk '{print $1}')"
    printf '  designated requirement: %s\n' "$(designated_requirement "$TARGET_APP")"
    printf '  nested Node signature and entitlements: valid\n'
    if test -n "$backup_app"; then
        printf '  previous bundle backup: %s\n' "$backup_app"
    fi
    printf 'No app was copied to /Applications or launched.\n'
}

require_tool "$SECURITY_BIN"
require_tool "$CODESIGN_BIN"
require_tool "$PLUTIL_BIN"
require_tool "$IDENTITY_AUDIT_BIN"
require_tool "$PROVENANCE_AUDIT_BIN"
require_tool "$SHASUM_BIN"

case " $* " in
    *" --initialize-requirement "*) die "--initialize-requirement is refused; the accepted requirement must not change" ;;
esac

mode="${1:---audit}"
case "$mode" in
    --audit|audit)
        test "$#" -le 1 || { usage; exit 2; }
        audit
        ;;
    --dry-run)
        test "$#" -eq 1 || { usage; exit 2; }
        dry_run
        ;;
    --stage)
        test "$#" -eq 2 || { usage; exit 2; }
        stage_app "$2"
        ;;
    --package)
        test "$#" -eq 1 || { usage; exit 2; }
        package_app
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CORE_SCRIPT="$REPO_ROOT/core/scripts/codexmulti-signing-identity.sh"
PACKAGE_SCRIPT="$REPO_ROOT/app/scripts/package-signed-macos.sh"
temp_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-signing-identity-test.XXXXXX")"

cleanup() {
    case "$temp_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-signing-identity-test.*) /bin/rm -rf -- "$temp_root" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$temp_root/bin" "$temp_root/pinned" "$temp_root/fallback"

printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
    'case "$1" in' \
    '    login-keychain) printf "\"%s\"\n" "$TEST_KEYCHAIN" ;;' \
    '    find-identity) printf "  1) %s \"%s\"\n     1 valid identities found\n" "$TEST_IDENTITY_HASH" "$TEST_IDENTITY_NAME" ;;' \
    '    find-certificate) printf "%s\n" "-----BEGIN CERTIFICATE-----" "fixture" "-----END CERTIFICATE-----" ;;' \
    '    *) exit 64 ;;' \
    'esac' > "$temp_root/bin/security"

printf '%s\n' '#!/bin/bash' 'set -euo pipefail' \
    'case " $* " in' \
    '    *" -text "*) printf "%s\n" "X509v3 Basic Constraints: critical" "    CA:TRUE, pathlen:0" "X509v3 Key Usage: critical" "    Digital Signature" "X509v3 Extended Key Usage: critical" "    Code Signing" ;;' \
    '    *" -checkend "*) exit 0 ;;' \
    '    *" -fingerprint "*) printf "SHA1 Fingerprint=%s\n" "$TEST_IDENTITY_FINGERPRINT" ;;' \
    '    *) exit 64 ;;' \
    'esac' > "$temp_root/bin/openssl"

printf '%s\n' '#!/bin/bash' 'exit 0' > "$temp_root/bin/noop"
chmod 755 "$temp_root/bin/security" "$temp_root/bin/openssl" "$temp_root/bin/noop"

PINNED_HASH="0123456789ABCDEF0123456789ABCDEF01234567"
OTHER_HASH="89ABCDEF0123456789ABCDEF0123456789ABCDEF"
PINNED_FINGERPRINT="01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67"
FALLBACK_NAME="CodexMulti Local Code Signing"
RENAMED_IDENTITY="Something Else Local Code Signing"
security_bin="$(PATH="$temp_root/bin:$PATH" command -v security)"

printf 'identifier "dev.codexmulti.app" and certificate root = H"%s"\n' "$PINNED_HASH" > "$temp_root/pinned/designated-requirement.txt"
printf '%s\n' "$PINNED_HASH" > "$temp_root/pinned/identity.sha1"
printf '%s\n' "$PINNED_HASH" > "$temp_root/fallback/identity.sha1"

run_resolver() {
    local script state_dir identity_hash identity_name
    script="$1"
    state_dir="$2"
    identity_hash="$3"
    identity_name="$4"
    PATH="$temp_root/bin:$PATH" \
    CODEXMULTI_SIGNING_STATE_DIR="$state_dir" \
    SECURITY_BIN="$security_bin" \
    TEST_KEYCHAIN="$temp_root/login.keychain-db" \
    TEST_IDENTITY_HASH="$identity_hash" \
    TEST_IDENTITY_NAME="$identity_name" \
    bash -c '. "$1"; single_identity_hash "$TEST_KEYCHAIN"' resolver "$script"
}

run_core_audit() {
    PATH="$temp_root/bin:$PATH" \
    CODEXMULTI_SIGNING_STATE_DIR="$temp_root/pinned" \
    SECURITY_BIN="$security_bin" \
    OPENSSL_BIN="$temp_root/bin/openssl" \
    TEST_KEYCHAIN="$temp_root/login.keychain-db" \
    TEST_IDENTITY_HASH="$PINNED_HASH" \
    TEST_IDENTITY_NAME="$RENAMED_IDENTITY" \
    TEST_IDENTITY_FINGERPRINT="$PINNED_FINGERPRINT" \
    "$CORE_SCRIPT" audit
}

run_package_audit() {
    PATH="$temp_root/bin:$PATH" \
    CODEXMULTI_SIGNING_STATE_DIR="$temp_root/pinned" \
    SECURITY_BIN="$security_bin" \
    CODESIGN_BIN="$temp_root/bin/noop" \
    PLUTIL_BIN="$temp_root/bin/noop" \
    IDENTITY_AUDIT_BIN="$temp_root/bin/noop" \
    PROVENANCE_AUDIT_BIN="$temp_root/bin/noop" \
    SHASUM_BIN="$temp_root/bin/noop" \
    TEST_KEYCHAIN="$temp_root/login.keychain-db" \
    TEST_IDENTITY_HASH="$PINNED_HASH" \
    TEST_IDENTITY_NAME="$RENAMED_IDENTITY" \
    bash -c '. "$1"; TARGET_APP="$2"; audit' package-audit "$PACKAGE_SCRIPT" "$temp_root/CodexMulti.app"
}

assert_hash() {
    local expected label output
    expected="$1"
    label="$2"
    shift 2
    if ! output="$("$@" 2>&1)"; then
        printf 'FAIL %s\n%s\n' "$label" "$output" >&2
        exit 1
    fi
    test "$output" = "$expected" || {
        printf 'FAIL %s returned %s\n' "$label" "$output" >&2
        exit 1
    }
}

assert_pinned_mismatch() {
    local label output
    label="$1"
    shift
    if output="$("$@" 2>&1)"; then
        printf 'FAIL %s unexpectedly succeeded\n' "$label" >&2
        exit 1
    fi
    printf '%s\n' "$output" | grep -F 'matching pinned certificate 01234567' >/dev/null || {
        printf 'FAIL %s omitted pinned-certificate context\n%s\n' "$label" "$output" >&2
        exit 1
    }
}

assert_contains() {
    local expected label output
    expected="$1"
    label="$2"
    shift 2
    if ! output="$("$@" 2>&1)"; then
        printf 'FAIL %s\n%s\n' "$label" "$output" >&2
        exit 1
    fi
    printf '%s\n' "$output" | grep -F "$expected" >/dev/null || {
        printf 'FAIL %s omitted %s\n%s\n' "$label" "$expected" "$output" >&2
        exit 1
    }
}

assert_hash "$PINNED_HASH" 'core resolves a renamed identity from the designated-requirement pin' \
    run_resolver "$CORE_SCRIPT" "$temp_root/pinned" "$PINNED_HASH" "$RENAMED_IDENTITY"
assert_hash "$PINNED_HASH" 'package resolves a renamed identity from the designated-requirement pin' \
    run_resolver "$PACKAGE_SCRIPT" "$temp_root/pinned" "$PINNED_HASH" "$RENAMED_IDENTITY"
assert_contains "pinned SHA-1: $PINNED_HASH" 'core audit follows the renamed pinned identity through certificate inspection' \
    run_core_audit
assert_contains "pinned SHA-1: $PINNED_HASH" 'package audit follows the renamed pinned identity' \
    run_package_audit

assert_pinned_mismatch 'core rejects identities that do not match the designated-requirement pin' \
    run_resolver "$CORE_SCRIPT" "$temp_root/pinned" "$OTHER_HASH" "$RENAMED_IDENTITY"
assert_pinned_mismatch 'package rejects identities that do not match the designated-requirement pin' \
    run_resolver "$PACKAGE_SCRIPT" "$temp_root/pinned" "$OTHER_HASH" "$RENAMED_IDENTITY"

assert_hash "$PINNED_HASH" 'core retains the identity-name fallback without a designated-requirement pin' \
    run_resolver "$CORE_SCRIPT" "$temp_root/fallback" "$PINNED_HASH" "$FALLBACK_NAME"
assert_hash "$PINNED_HASH" 'package retains the identity-name fallback without a designated-requirement pin' \
    run_resolver "$PACKAGE_SCRIPT" "$temp_root/fallback" "$PINNED_HASH" "$FALLBACK_NAME"

printf 'PASS signing identity resolution prefers the designated-requirement certificate pin and retains the name fallback\n'

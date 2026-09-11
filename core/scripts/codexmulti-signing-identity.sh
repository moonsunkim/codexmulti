#!/bin/bash

set -euo pipefail

IDENTITY_NAME="CodexMulti Local Code Signing"
VALID_DAYS=3650
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
STATE_DIR="${CODEXMULTI_SIGNING_STATE_DIR:-$PROJECT_DIR/.local-signing}"
FINGERPRINT_FILE="$STATE_DIR/identity.sha1"
REQUIREMENT_FILE="$STATE_DIR/designated-requirement.txt"
OPENSSL_BIN="${OPENSSL_BIN:-/usr/bin/openssl}"
SECURITY_BIN="${SECURITY_BIN:-/usr/bin/security}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Usage:
  scripts/codexmulti-signing-identity.sh [audit]
  scripts/codexmulti-signing-identity.sh bootstrap --apply
  scripts/codexmulti-signing-identity.sh remove --apply --fingerprint SHA1

audit is read-only and is the default. bootstrap and remove mutate the user's
login Keychain and must only be run after explicit user authorization.
EOF
}

require_tool() {
    test -x "$1" || die "required tool is unavailable: $1"
}

login_keychain() {
    local output path
    output="$($SECURITY_BIN login-keychain 2>&1)" || die "cannot resolve the user login Keychain: $output"
    path="$(printf '%s\n' "$output" | sed -nE 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/p' | sed -n '1p')"
    test -n "$path" || die "security login-keychain returned an unrecognized value: $output"
    case "$path" in
        /*) ;;
        *) die "login Keychain is not an absolute path: $path" ;;
    esac
    printf '%s\n' "$path"
}

identity_hashes() {
    local keychain output
    keychain="$1"
    output="$($SECURITY_BIN find-identity -v -p codesigning "$keychain" 2>&1 || true)"
    printf '%s\n' "$output" |
        sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-Fa-f]{40}) "CodexMulti Local Code Signing"[[:space:]]*$/\1/p' |
        tr '[:lower:]' '[:upper:]'
}

single_identity_hash() {
    local keychain hashes count
    keychain="$1"
    hashes="$(identity_hashes "$keychain")"
    count="$(printf '%s\n' "$hashes" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
    test "$count" = "1" || die "expected exactly one valid '$IDENTITY_NAME' identity in $keychain; found $count"
    printf '%s\n' "$hashes"
}

read_pinned_hash() {
    local value
    test -f "$FINGERPRINT_FILE" || die "missing machine-local identity pin: $FINGERPRINT_FILE"
    value="$(tr -d '[:space:]' < "$FINGERPRINT_FILE" | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "$value" | grep -Eq '^[0-9A-F]{40}$' || die "invalid SHA-1 identity pin in $FINGERPRINT_FILE"
    printf '%s\n' "$value"
}

verify_certificate_profile() {
    local text basic_constraints key_usage extended_key_usage
    text="$1"
    basic_constraints="$(printf '%s\n' "$text" | awk '/X509v3 Basic Constraints: critical/{getline; sub(/^[[:space:]]*/, ""); print}')"
    key_usage="$(printf '%s\n' "$text" | awk '/X509v3 Key Usage: critical/{getline; sub(/^[[:space:]]*/, ""); print}')"
    extended_key_usage="$(printf '%s\n' "$text" | awk '/X509v3 Extended Key Usage: critical/{getline; sub(/^[[:space:]]*/, ""); print}')"
    test "$basic_constraints" = "CA:TRUE, pathlen:0" || die "identity certificate lacks the expected critical self-signed-root constraint"
    test "$key_usage" = "Digital Signature" || die "identity certificate key usage is not exactly critical Digital Signature"
    test "$extended_key_usage" = "Code Signing" || die "identity certificate extended key usage is not exactly critical Code Signing"
}

audit_identity() {
    local keychain live_hash pinned_hash pem cert_text cert_hash summary
    keychain="$(login_keychain)"
    live_hash="$(single_identity_hash "$keychain")"
    pinned_hash="$(read_pinned_hash)"
    test "$live_hash" = "$pinned_hash" || die "identity pin mismatch: Keychain has $live_hash but local state expects $pinned_hash"

    pem="$($SECURITY_BIN find-certificate -c "$IDENTITY_NAME" -p "$keychain" 2>&1)" || die "cannot export the public certificate for inspection"
    cert_text="$(printf '%s\n' "$pem" | "$OPENSSL_BIN" x509 -noout -text 2>&1)" || die "cannot inspect the identity certificate"
    verify_certificate_profile "$cert_text"
    cert_hash="$(printf '%s\n' "$pem" | "$OPENSSL_BIN" x509 -noout -fingerprint -sha1 | sed -E 's/^.*=//' | tr -d ':' | tr '[:lower:]' '[:upper:]')"
    test "$cert_hash" = "$live_hash" || die "public certificate does not match the valid identity fingerprint"
    printf '%s\n' "$pem" | "$OPENSSL_BIN" x509 -noout -checkend 15552000 >/dev/null 2>&1 || die "identity certificate expires within 180 days; plan an explicit signer migration"
    summary="$(printf '%s\n' "$pem" | "$OPENSSL_BIN" x509 -noout -subject -issuer -dates -fingerprint -sha1 2>&1)" || die "cannot summarize the identity certificate"

    printf 'CodexMulti signing identity: ready\n'
    printf '  login Keychain: %s\n' "$keychain"
    printf '  identity: %s\n' "$IDENTITY_NAME"
    printf '  pinned SHA-1: %s\n' "$live_hash"
    printf '  validity requested at bootstrap: %s days\n' "$VALID_DAYS"
    printf '%s\n' "$summary" | sed 's/^/  /'
    printf '  user trust: trustRoot, constrained to the Code Signing policy\n'
}

bootstrap_identity() {
    local keychain existing_cert tmp_dir key_path cert_path config_path p12_path
    local key_password p12_password cert_hash imported_hash cert_text
    local identity_imported bootstrap_committed
    keychain="$(login_keychain)"
    identity_imported=no
    bootstrap_committed=no

    if test -n "$(identity_hashes "$keychain")"; then
        die "a valid '$IDENTITY_NAME' identity already exists; audit it instead of replacing it"
    fi
    if test -e "$FINGERPRINT_FILE" || test -e "$REQUIREMENT_FILE"; then
        die "stale machine-local signing state exists in $STATE_DIR; inspect and explicitly remove or archive it before creating a different signer"
    fi
    existing_cert="$($SECURITY_BIN find-certificate -c "$IDENTITY_NAME" -p "$keychain" 2>/dev/null || true)"
    test -z "$existing_cert" || die "a certificate matching '$IDENTITY_NAME' already exists without one unambiguous valid identity; resolve it manually"

    umask 077
    tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/codexmulti-signing.XXXXXX")"
    case "$tmp_dir" in
        "${TMPDIR:-/tmp}"/codexmulti-signing.*) ;;
        *) die "mktemp returned an unexpected path: $tmp_dir" ;;
    esac
    key_path="$tmp_dir/identity-key.pem"
    cert_path="$tmp_dir/identity-cert.pem"
    config_path="$tmp_dir/openssl.cnf"
    p12_path="$tmp_dir/identity.p12"

    cleanup_bootstrap() {
        key_password=""
        p12_password=""
        if test "${identity_imported:-no}" = "yes" && test "${bootstrap_committed:-no}" != "yes"; then
            "$SECURITY_BIN" delete-identity -Z "$cert_hash" -t "$keychain" >/dev/null 2>&1 || true
            identity_imported=no
            rm -f -- "$FINGERPRINT_FILE"
        fi
        if test -n "${tmp_dir:-}" && test -d "$tmp_dir"; then
            case "$tmp_dir" in
                "${TMPDIR:-/tmp}"/codexmulti-signing.*) rm -rf -- "$tmp_dir" ;;
            esac
        fi
    }
    trap cleanup_bootstrap EXIT
    trap 'cleanup_bootstrap; exit 1' HUP INT TERM

    cat > "$config_path" <<'EOF'
[req]
prompt = no
distinguished_name = subject
x509_extensions = codesign

[subject]
CN = CodexMulti Local Code Signing
O = CodexMulti Local Development
OU = Single Mac Local Signing

[codesign]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

    key_password="$($OPENSSL_BIN rand -hex 32)"
    p12_password="$($OPENSSL_BIN rand -hex 32)"
    "$OPENSSL_BIN" req -new -x509 -newkey rsa:3072 -sha256 -days "$VALID_DAYS" -set_serial 1 \
        -config "$config_path" -keyout "$key_path" -out "$cert_path" \
        -passout "pass:$key_password"

    cert_text="$("$OPENSSL_BIN" x509 -in "$cert_path" -noout -text 2>&1)" || die "cannot inspect the generated certificate"
    verify_certificate_profile "$cert_text"
    cert_hash="$($OPENSSL_BIN x509 -in "$cert_path" -noout -fingerprint -sha1 | sed -E 's/^.*=//' | tr -d ':' | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "$cert_hash" | grep -Eq '^[0-9A-F]{40}$' || die "could not derive the generated certificate SHA-1"

    "$OPENSSL_BIN" pkcs12 -export -inkey "$key_path" -in "$cert_path" -out "$p12_path" \
        -name "$IDENTITY_NAME" -passin "pass:$key_password" -passout "pass:$p12_password"






    identity_imported=yes
    if ! "$SECURITY_BIN" import "$p12_path" -k "$keychain" -f pkcs12 -x \
        -P "$p12_password" -T /usr/bin/codesign; then
        die "identity import failed"
    fi




    if ! "$SECURITY_BIN" add-trusted-cert -r trustRoot -p codeSign -k "$keychain" "$cert_path"; then
        die "the Code Signing-only user trust setting was not accepted; the imported identity will be removed"
    fi

    imported_hash="$(identity_hashes "$keychain")"
    if test "$imported_hash" != "$cert_hash"; then
        die "trusted identity did not become the one unambiguous valid Code Signing identity; it will be removed"
    fi

    mkdir -p "$STATE_DIR"
    printf '%s\n' "$cert_hash" > "$FINGERPRINT_FILE"
    chmod 600 "$FINGERPRINT_FILE"
    audit_identity
    bootstrap_committed=yes
    cleanup_bootstrap
    trap - EXIT HUP INT TERM
}

remove_identity() {
    local requested_hash keychain live_hash pinned_hash
    requested_hash="$1"
    requested_hash="$(printf '%s' "$requested_hash" | tr '[:lower:]' '[:upper:]')"
    printf '%s\n' "$requested_hash" | grep -Eq '^[0-9A-F]{40}$' || die "--fingerprint must be exactly 40 hexadecimal characters"

    keychain="$(login_keychain)"
    live_hash="$(single_identity_hash "$keychain")"
    pinned_hash="$(read_pinned_hash)"
    test "$requested_hash" = "$live_hash" || die "requested fingerprint does not match the live identity"
    test "$requested_hash" = "$pinned_hash" || die "requested fingerprint does not match the machine-local pin"

    "$SECURITY_BIN" delete-identity -Z "$requested_hash" -t "$keychain"
    rm -f -- "$FINGERPRINT_FILE" "$REQUIREMENT_FILE"
    rmdir "$STATE_DIR" 2>/dev/null || true
    printf 'Removed only the CodexMulti signing identity %s from %s.\n' "$requested_hash" "$keychain"
    printf 'Existing app-owned Keychain password items were not removed.\n'
}

require_tool "$OPENSSL_BIN"
require_tool "$SECURITY_BIN"

mode="${1:-audit}"
case "$mode" in
    audit|--audit|--dry-run)
        test "$#" -le 1 || { usage; exit 2; }
        audit_identity
        ;;
    bootstrap)
        test "$#" -eq 2 && test "$2" = "--apply" || die "bootstrap requires the explicit --apply flag"
        bootstrap_identity
        ;;
    remove)
        test "$#" -eq 4 && test "$2" = "--apply" && test "$3" = "--fingerprint" ||
            die "remove requires: remove --apply --fingerprint SHA1"
        remove_identity "$4"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac

#!/bin/bash

set -euo pipefail

NODE_VERSION="v26.8.1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
ARCHIVE_NAME="node-$NODE_VERSION-darwin-arm64.tar.gz"
ARCHIVE_ROOT="node-$NODE_VERSION-darwin-arm64"
DIST_URL="https://nodejs.org/dist/$NODE_VERSION"
NODE_DESTINATION="$PROJECT_DIR/.node/$NODE_VERSION/bin/node"
LICENSE_DESTINATION="$PROJECT_DIR/.node/$NODE_VERSION/LICENSE"
CURL_BIN="${CURL_BIN:-/usr/bin/curl}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
TAR_BIN="${TAR_BIN:-/usr/bin/tar}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_tool() {
    test -x "$1" || die "required tool is unavailable: $1"
}

verify_sha256() {
    local file expected actual
    file="$1"
    expected="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    test -f "$file" || die "SHA-256 input is missing: $file"
    printf '%s\n' "$expected" | grep -Eq '^[0-9a-f]{64}$' ||
        die "expected SHA-256 is not 64 hexadecimal characters"
    actual="$("$SHASUM_BIN" -a 256 "$file" | awk '{print $1}')" ||
        die "could not calculate SHA-256: $file"
    test "$actual" = "$expected" ||
        die "SHA-256 mismatch for $file: expected $expected, got $actual"
}

if test "${1:-}" = "--verify-sha256"; then
    test "$#" -eq 3 || die "usage: scripts/fetch-node.sh --verify-sha256 <file> <sha256>"
    require_tool "$SHASUM_BIN"
    verify_sha256 "$2" "$3"
    printf 'SHA-256 verification: PASS (%s)\n' "$2"
    exit 0
fi
test "$#" -eq 0 || die "usage: scripts/fetch-node.sh [--verify-sha256 <file> <sha256>]"

require_tool "$CURL_BIN"
require_tool "$SHASUM_BIN"
require_tool "$TAR_BIN"
test "$(uname -s)" = "Darwin" || die "the pinned Node runtime requires macOS"
test "$(uname -m)" = "arm64" || die "the pinned Node runtime requires arm64 macOS"

temporary_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-node.XXXXXX")"
temporary_node=""
temporary_license=""
cleanup() {
    case "$temporary_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-node.*) /bin/rm -rf -- "$temporary_root" ;;
    esac
    case "$temporary_node" in
        "$PROJECT_DIR"/.node/"$NODE_VERSION"/bin/.node.*) /bin/rm -f -- "$temporary_node" ;;
    esac
    case "$temporary_license" in
        "$PROJECT_DIR"/.node/"$NODE_VERSION"/.LICENSE.*) /bin/rm -f -- "$temporary_license" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

archive="$temporary_root/$ARCHIVE_NAME"
checksums="$temporary_root/SHASUMS256.txt"
extract_root="$temporary_root/extracted"
mkdir -p "$extract_root"

"$CURL_BIN" --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$checksums" "$DIST_URL/SHASUMS256.txt" ||
    die "failed to download the official Node SHA-256 manifest"
"$CURL_BIN" --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$archive" "$DIST_URL/$ARCHIVE_NAME" ||
    die "failed to download the pinned Node archive"

published_hashes="$(awk -v name="$ARCHIVE_NAME" '$2 == name { print $1 }' "$checksums")"
published_count="$(printf '%s\n' "$published_hashes" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
test "$published_count" = "1" ||
    die "official SHA-256 manifest does not contain exactly one entry for $ARCHIVE_NAME"
published_sha256="$(printf '%s\n' "$published_hashes" | sed -n '1p')"
verify_sha256 "$archive" "$published_sha256"

"$TAR_BIN" -xzf "$archive" -C "$extract_root" "$ARCHIVE_ROOT/bin/node" "$ARCHIVE_ROOT/LICENSE" ||
    die "failed to extract Node and LICENSE from the verified archive"
extracted_node="$extract_root/$ARCHIVE_ROOT/bin/node"
extracted_license="$extract_root/$ARCHIVE_ROOT/LICENSE"
test -f "$extracted_node" || die "verified archive did not contain bin/node"
test ! -L "$extracted_node" || die "verified archive contained a symlink at bin/node"
test -s "$extracted_license" || die "verified archive did not contain a non-empty LICENSE"
test ! -L "$extracted_license" || die "verified archive contained a symlink at LICENSE"
chmod 0755 "$extracted_node"
test "$("$extracted_node" --version)" = "$NODE_VERSION" ||
    die "extracted Node version does not match the pin $NODE_VERSION"

mkdir -p "$(dirname "$NODE_DESTINATION")"
temporary_node="$(mktemp "$(dirname "$NODE_DESTINATION")/.node.XXXXXX")"
temporary_license="$(mktemp "$(dirname "$LICENSE_DESTINATION")/.LICENSE.XXXXXX")"
/bin/cp -f "$extracted_node" "$temporary_node"
/bin/cp -f "$extracted_license" "$temporary_license"
chmod 0755 "$temporary_node"
/bin/mv -f "$temporary_license" "$LICENSE_DESTINATION"
temporary_license=""
/bin/mv -f "$temporary_node" "$NODE_DESTINATION"
temporary_node=""
printf 'Installed Node %s: %s\n' "$NODE_VERSION" "$NODE_DESTINATION"
printf '  license: %s\n' "$LICENSE_DESTINATION"
printf '  verified archive SHA-256: %s\n' "$published_sha256"

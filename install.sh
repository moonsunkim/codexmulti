#!/bin/bash

set -euo pipefail

REPOSITORY="moonsunkim/codexmulti"
API_URL="https://api.github.com/repos/$REPOSITORY/releases/latest"
CURL_BIN="/usr/bin/curl"
PLUTIL_BIN="/usr/bin/plutil"
SHASUM_BIN="/usr/bin/shasum"
DITTO_BIN="/usr/bin/ditto"
OPEN_BIN="/usr/bin/open"
CODESIGN_BIN="/usr/bin/codesign"
TARGET_APP="/Applications/CodexMulti.app"
PREVIOUS_APP="/Applications/CodexMulti.app.previous"
STAGED_APP="/Applications/.CodexMulti.app.install.$$"
temporary_root=""
install_started=no
install_committed=no
previous_created=no

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_tool() {
    test -x "$1" || die "required tool is unavailable: $1"
}

install_command() {
    if test -w /Applications; then
        "$@"
    else
        /usr/bin/sudo "$@"
    fi
}

cleanup() {
    if test "$install_started" = yes && test "$install_committed" != yes; then
        if test "$previous_created" = yes && test ! -e "$TARGET_APP" && test -e "$PREVIOUS_APP"; then
            install_command /bin/mv "$PREVIOUS_APP" "$TARGET_APP" || true
        fi
    fi
    if test -e "$STAGED_APP"; then
        install_command /bin/rm -rf -- "$STAGED_APP" || true
    fi
    if test -n "$temporary_root" && test -d "$temporary_root"; then
        case "$temporary_root" in
            "${TMPDIR:-/private/tmp}"/codexmulti-install.*) /bin/rm -rf -- "$temporary_root" ;;
        esac
    fi
}
trap cleanup EXIT HUP INT TERM

require_tool "$CURL_BIN"
require_tool "$PLUTIL_BIN"
require_tool "$SHASUM_BIN"
require_tool "$DITTO_BIN"
require_tool "$OPEN_BIN"
require_tool "$CODESIGN_BIN"
test "$(uname -s)" = Darwin || die "CodexMulti requires macOS"
test "$(uname -m)" = arm64 || die "CodexMulti requires Apple Silicon"
macos_version="$(/usr/bin/sw_vers -productVersion)"
macos_major="${macos_version%%.*}"
printf '%s\n' "$macos_major" | grep -Eq '^[0-9]+$' || die "could not determine the macOS version"
test "$macos_major" -ge 26 || die "CodexMulti requires macOS 26 or later; found $macos_version"
test -d /Applications || die "/Applications is unavailable"

temporary_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-install.XXXXXX")"
release_json="$temporary_root/release.json"
"$CURL_BIN" --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --header 'Accept: application/vnd.github+json' --header 'X-GitHub-Api-Version: 2022-11-28' \
    --user-agent 'CodexMulti installer' --output "$release_json" "$API_URL" ||
    die "failed to read the latest GitHub release"
tag="$($PLUTIL_BIN -extract tag_name raw -o - "$release_json" 2>/dev/null || true)"
case "$tag" in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) die "latest release has an invalid tag: ${tag:-missing}" ;;
esac
version="${tag#v}"
printf '%s\n' "$version" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$' ||
    die "latest release has an invalid version: $version"
release_body="$($PLUTIL_BIN -extract body raw -o - "$release_json" 2>/dev/null || true)"
zip_name="CodexMulti-$version.zip"
sha_name="$zip_name.sha256"
asset_root="https://github.com/$REPOSITORY/releases/download/$tag"
zip_path="$temporary_root/$zip_name"
sha_path="$temporary_root/$sha_name"
"$CURL_BIN" --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$zip_path" "$asset_root/$zip_name" || die "failed to download $zip_name"
"$CURL_BIN" --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$sha_path" "$asset_root/$sha_name" || die "failed to download $sha_name"

published_hashes="$(awk -v name="$zip_name" '$2 == name { print $1 }' "$sha_path")"
published_count="$(printf '%s\n' "$published_hashes" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
test "$published_count" = 1 || die "checksum file does not contain exactly one entry for $zip_name"
expected_sha256="$(printf '%s\n' "$published_hashes" | sed -n '1p' | tr '[:upper:]' '[:lower:]')"
printf '%s\n' "$expected_sha256" | grep -Eq '^[0-9a-f]{64}$' || die "published SHA-256 is invalid"
actual_sha256="$($SHASUM_BIN -a 256 "$zip_path" | awk '{print $1}')"
test "$actual_sha256" = "$expected_sha256" ||
    die "SHA-256 mismatch for $zip_name: expected $expected_sha256, got $actual_sha256"
printf 'SHA-256 verified: %s\n' "$actual_sha256"

extract_root="$temporary_root/extracted"
mkdir -p "$extract_root"
"$DITTO_BIN" -x -k "$zip_path" "$extract_root"
extracted_app="$extract_root/CodexMulti.app"
test -d "$extracted_app" || die "release archive does not contain CodexMulti.app"
test ! -L "$extracted_app" || die "release archive contains a symlink instead of CodexMulti.app"
test -x "$extracted_app/Contents/MacOS/CodexMulti" || die "release app executable is missing"

if printf '%s\n' "$release_body" | grep -F '**Signing: UNSIGNED**' >/dev/null; then
    printf 'Warning: this release is unsigned.\n' >&2
else
    "$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$extracted_app" || die "app signature verification failed"
    printf 'Code signature verified.\n'
fi

test ! -e "$STAGED_APP" || die "installation staging path already exists: $STAGED_APP"
install_command "$DITTO_BIN" "$extracted_app" "$STAGED_APP"
test -d "$STAGED_APP" || die "could not stage CodexMulti.app in /Applications"
install_started=yes
if test -e "$TARGET_APP"; then
    if test -e "$PREVIOUS_APP"; then
        install_command /bin/rm -rf -- "$PREVIOUS_APP"
    fi
    install_command /bin/mv "$TARGET_APP" "$PREVIOUS_APP"
    previous_created=yes
fi
if ! install_command /bin/mv "$STAGED_APP" "$TARGET_APP"; then
    if test "$previous_created" = yes && test -e "$PREVIOUS_APP" && test ! -e "$TARGET_APP"; then
        install_command /bin/mv "$PREVIOUS_APP" "$TARGET_APP" || true
    fi
    die "installation failed; the previous app was restored when available"
fi
install_committed=yes

if printf '%s\n' "$release_body" | grep -F '**Notarization: NOTARIZED**' >/dev/null; then
    printf 'Notarization status: notarized.\n'
else
    printf 'This release is not notarized. On first launch, Control-click CodexMulti.app, choose Open, then Open.\n'
fi
printf 'Installed CodexMulti %s at %s\n' "$version" "$TARGET_APP"
if test -e "$PREVIOUS_APP"; then
    printf 'Previous app retained at %s\n' "$PREVIOUS_APP"
fi
"$OPEN_BIN" -g "$TARGET_APP"

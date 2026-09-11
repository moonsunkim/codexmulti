#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/../build-metadata.sh"

temp_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-build-version.XXXXXX")"
cleanup() {
    case "$temp_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-build-version.*) /bin/rm -rf -- "$temp_root" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

printf '0.1.0\n' > "$temp_root/VERSION"
VERSION_FILE="$temp_root/VERSION"
resolve_build_metadata

test "$APP_VERSION" = "0.1.0" || {
    printf 'FAIL build metadata preserves VERSION: %s\n' "$APP_VERSION" >&2
    exit 1
}
printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[0-9]{12}$' || {
    printf 'FAIL build metadata emits a 12-digit build number: %s\n' "$BUILD_NUMBER" >&2
    exit 1
}

printf 'PASS build metadata preserves VERSION and emits a 12-digit UTC build number\n'

#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
ICON_SOURCE="$REPO_ROOT/assets/icon/icon-1024.png"
ICON_OUTPUT="$PROJECT_DIR/Resources/AppIcon.icns"
SIPS_BIN="${SIPS_BIN:-/usr/bin/sips}"
ICONUTIL_BIN="${ICONUTIL_BIN:-/usr/bin/iconutil}"
ICNS_FALLBACK_BIN="${ICNS_FALLBACK_BIN:-$SCRIPT_DIR/make-icns.pl}"
STAT_BIN="${STAT_BIN:-/usr/bin/stat}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

test -x "$SIPS_BIN" || die "sips is unavailable: $SIPS_BIN"
test -x "$ICONUTIL_BIN" || die "iconutil is unavailable: $ICONUTIL_BIN"
test -x "$ICNS_FALLBACK_BIN" || die "ICNS fallback is unavailable: $ICNS_FALLBACK_BIN"
test -x "$STAT_BIN" || die "stat is unavailable: $STAT_BIN"
test -f "$ICON_SOURCE" || die "icon source is missing: $ICON_SOURCE"

source_width="$("$SIPS_BIN" -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth:/ { print $2 }')"
source_height="$("$SIPS_BIN" -g pixelHeight "$ICON_SOURCE" | awk '/pixelHeight:/ { print $2 }')"
test "$source_width" = 1024 && test "$source_height" = 1024 ||
    die "icon source must be 1024x1024: ${source_width}x${source_height}"

temp_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-icon.XXXXXX")"
iconset="$temp_root/AppIcon.iconset"
mkdir -p "$iconset"

cleanup() {
    case "$temp_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-icon.*) /bin/rm -rf -- "$temp_root" ;;
    esac
}
trap cleanup EXIT

for size in 16 32 128 256 512; do
    "$SIPS_BIN" -z "$size" "$size" "$ICON_SOURCE" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    "$SIPS_BIN" -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

printf 'Icon source: %s (%sx%s)\n' "$ICON_SOURCE" "$source_width" "$source_height"
printf 'Generated AppIcon.iconset:\n'
for image in "$iconset"/*.png; do
    width="$("$SIPS_BIN" -g pixelWidth "$image" | awk '/pixelWidth:/ { print $2 }')"
    height="$("$SIPS_BIN" -g pixelHeight "$image" | awk '/pixelHeight:/ { print $2 }')"
    printf '  %s: %sx%s\n' "$(basename "$image")" "$width" "$height"
done

temp_output="$temp_root/AppIcon.icns"
if ! "$ICONUTIL_BIN" -c icns "$iconset" -o "$temp_output" || test ! -s "$temp_output"; then
    printf 'iconutil could not create an ICNS on this macOS; using the compatible ICNS container writer\n'
    "$ICNS_FALLBACK_BIN" "$iconset" "$temp_output"
fi
/bin/cp -f "$temp_output" "$ICON_OUTPUT"
printf 'Generated %s: %s bytes\n' "$ICON_OUTPUT" "$("$STAT_BIN" -f %z "$ICON_OUTPUT")"

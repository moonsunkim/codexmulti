#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
BUNDLE="$PROJECT_DIR/dist/staging/CodexMulti.app"
EXECUTABLE="$BUNDLE/Contents/MacOS/CodexMulti"
FIXTURE="$REPO_ROOT/core/fixtures/bridge/viewstate-proxy-reachable-mapped.json"
EXPANDED_FIXTURE="$PROJECT_DIR/fixtures/showcase/accounts-expanded.json"
OUTPUT_DIR="$REPO_ROOT/assets/screenshots"
LSAPPINFO="/usr/bin/lsappinfo"
SIPS="/usr/bin/sips"
STAT="/usr/bin/stat"
PLUTIL="/usr/bin/plutil"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

test -x "$LSAPPINFO" || die "lsappinfo is unavailable: $LSAPPINFO"
test -x "$SIPS" || die "sips is unavailable: $SIPS"
test -x "$STAT" || die "stat is unavailable: $STAT"
test -x "$PLUTIL" || die "plutil is unavailable: $PLUTIL"
test -f "$FIXTURE" || die "fixture is missing: $FIXTURE"
test -f "$EXPANDED_FIXTURE" || die "fixture is missing: $EXPANDED_FIXTURE"

validate_synthetic_fixture() {
    local fixture emails
    fixture="$1"
    emails="$(/usr/bin/grep -Eio '[[:alnum:]._%+-]+@[[:alnum:].-]+[.][[:alpha:]]{2,}' "$fixture" || true)"
    test -n "$emails" || die "fixture contains no synthetic email identities: $fixture"
    if printf '%s\n' "$emails" | /usr/bin/grep -Ev '@example[.][[:alnum:].-]+$' >/dev/null; then
        die "fixture contains a forbidden real-account domain: $fixture"
    fi
}

validate_synthetic_fixture "$FIXTURE"
validate_synthetic_fixture "$EXPANDED_FIXTURE"

if test ! -x "$EXECUTABLE"; then
    printf 'Staging bundle not found; building %s\n' "$BUNDLE"
    "$SCRIPT_DIR/build-app.sh"
fi
test -x "$EXECUTABLE" || die "staging executable is missing after build: $EXECUTABLE"
short_version="$($PLUTIL -extract CFBundleShortVersionString raw -o - "$BUNDLE/Contents/Info.plist")"
build_version="$($PLUTIL -extract CFBundleVersion raw -o - "$BUNDLE/Contents/Info.plist")"
if test "$short_version" = "$build_version"; then
    version_text="$short_version"
else
    version_text="$short_version ($build_version)"
fi

mkdir -p "$OUTPUT_DIR"
lifecycle_log="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-screenshots-lifecycle.XXXXXX")"
runner_root="$(mktemp -d "$PROJECT_DIR/dist/staging/.screenshot-runner.XXXXXX")"
runner="$runner_root/CodexMulti"




/bin/cp -f "$EXECUTABLE" "$runner"
chmod 0755 "$runner"
cleanup() {
    /bin/rm -f -- "$lifecycle_log"
    case "$runner_root" in
        "$PROJECT_DIR"/dist/staging/.screenshot-runner.*) /bin/rm -rf -- "$runner_root" ;;
    esac
}
trap cleanup EXIT

front_before="$($LSAPPINFO front)"
printf 'Front application before: %s\n' "$front_before"

capture_one() {
    local name appearance tab fixture frame output
    name="$1"
    appearance="$2"
    tab="$3"
    fixture="$4"
    frame="$5"
    output="$OUTPUT_DIR/$name"
    printf 'Rendering %s (%s, %s)\n' "$output" "$appearance" "$tab"
    CODEXMULTI_LIFECYCLE_LOG="$lifecycle_log" \
    CODEXMULTI_CAPTURE_VERSION_TEXT="$version_text" \
    "$runner" \
        "--fixture=$fixture" \
        "--capture=$output" \
        "--frame=$frame" \
        --no-activate \
        --no-status-item \
        "--tab=$tab" \
        "--set-appearance=$appearance"
    test -s "$output" || die "capture is missing or empty: $output"
}

capture_one accounts-expanded-light.png light accounts "$EXPANDED_FIXTURE" 0,0,1000,780
capture_one accounts-expanded-dark.png dark accounts "$EXPANDED_FIXTURE" 0,0,1000,780
capture_one accounts-light.png light accounts "$FIXTURE" 0,0,1000,700
capture_one accounts-dark.png dark accounts "$FIXTURE" 0,0,1000,700
capture_one settings-light.png light settings "$FIXTURE" 0,0,1000,780
capture_one settings-dark.png dark settings "$FIXTURE" 0,0,1000,780

front_after="$($LSAPPINFO front)"
printf 'Front application after:  %s\n' "$front_after"
test "$front_before" = "$front_after" ||
    die "front application changed during off-screen capture"
printf 'Front application unchanged.\n'

for output in "$OUTPUT_DIR"/*.png; do
    printf '%s: %s bytes\n' "$output" "$($STAT -f %z "$output")"
    "$SIPS" -g pixelWidth -g pixelHeight "$output"
done

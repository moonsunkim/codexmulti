#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${RELEASE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd -P)}"
VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/VERSION}"
CHANGELOG_FILE="${CHANGELOG_FILE:-$REPO_ROOT/CHANGELOG.md}"
CASK_FILE="${CASK_FILE:-$REPO_ROOT/homebrew/Casks/codexmulti.rb}"
DIST_DIR="${RELEASE_DIST_DIR:-$REPO_ROOT/dist}"
STAGE_PARENT="${RELEASE_STAGE_PARENT:-/private/tmp}"
UNSIGNED_APP="${UNSIGNED_APP:-$REPO_ROOT/app/dist/staging/CodexMulti.app}"
BUILD_BIN="${BUILD_BIN:-$REPO_ROOT/app/scripts/build-app.sh}"
PACKAGE_BIN="${PACKAGE_BIN:-$REPO_ROOT/app/scripts/package-signed-macos.sh}"
PROVENANCE_BIN="${PROVENANCE_BIN:-$REPO_ROOT/app/scripts/verify-provenance.sh}"
PROXY_VERIFY_BIN="${PROXY_VERIFY_BIN:-$REPO_ROOT/app/scripts/verify-bundled-proxy.sh}"
GIT_BIN="${GIT_BIN:-git}"
GH_BIN="${GH_BIN:-gh}"
DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"
SHASUM_BIN="${SHASUM_BIN:-/usr/bin/shasum}"
XCRUN_BIN="${XCRUN_BIN:-/usr/bin/xcrun}"
RELEASE_REPOSITORY="${RELEASE_REPOSITORY:-moonsunkim/codexmulti}"
RELEASE_BRANCH="${RELEASE_BRANCH:-main}"
CURRENT_STAGE="initialization"
RELEASE_MODE="release"
VERSION=""
TAG=""
STAGE_ROOT=""
STAGED_APP=""
ZIP_PATH=""
SHA_PATH=""
NOTES_PATH=""
ARTIFACT_SHA256=""
SIGNING_STATUS=""
NOTARIZATION_STATUS=""

die() {
    printf 'error: release stage %s: %s\n' "$CURRENT_STAGE" "$*" >&2
    exit 1
}

fail_stage() {
    local status
    status="$1"
    trap - ERR
    printf 'error: release stage %s failed with status %s\n' "$CURRENT_STAGE" "$status" >&2
    exit "$status"
}

begin_stage() {
    CURRENT_STAGE="$1"
    printf '==> %s\n' "$CURRENT_STAGE"
}

require_tool() {
    case "$1" in
        */*) test -x "$1" ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
    esac || die "required tool is unavailable: $1"
}

read_release_version() {
    local value lines
    test -f "$VERSION_FILE" || die "VERSION file is missing: $VERSION_FILE"
    lines="$(awk 'END { print NR + 0 }' "$VERSION_FILE")"
    test "$lines" = 1 || die "VERSION must contain exactly one line"
    value="$(sed -n '1p' "$VERSION_FILE")"
    printf '%s\n' "$value" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$' ||
        die "VERSION is invalid: $value"
    printf '%s\n' "$value"
}

extract_changelog_section() {
    local section input output
    section="$1"
    input="$2"
    output="$3"
    awk -v section="$section" '
        $0 == "## [" section "]" || $0 == "## " section { found = 1; capture = 1; next }
        capture && /^## / { exit }
        capture { lines[++count] = $0 }
        END {
            if (!found) exit 4
            first = 1
            while (first <= count && lines[first] == "") first++
            last = count
            while (last >= first && lines[last] == "") last--
            for (line_number = first; line_number <= last; line_number++) print lines[line_number]
        }
    ' "$input" > "$output"
    test -s "$output" || return 1
}

check_clean_checkout() {
    local status branch
    status="$("$GIT_BIN" -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
    test -z "$status" || die "working tree is not clean"
    branch="$("$GIT_BIN" -C "$REPO_ROOT" branch --show-current)"
    test "$branch" = "$RELEASE_BRANCH" || die "release must run from $RELEASE_BRANCH, found ${branch:-detached HEAD}"
}

check_ci_success() {
    local head result run_head run_status run_conclusion tab
    head="$("$GIT_BIN" -C "$REPO_ROOT" rev-parse HEAD)"
    result="$("$GH_BIN" run list --repo "$RELEASE_REPOSITORY" --workflow ci.yml --commit "$head" --limit 1 \
        --json headSha,status,conclusion --jq '.[0] | [.headSha, .status, .conclusion] | @tsv')"
    tab="$(printf '\t')"
    IFS="$tab" read -r run_head run_status run_conclusion <<EOF
$result
EOF
    test "$run_head" = "$head" || die "no CI run found for HEAD $head"
    test "$run_status" = completed || die "CI is not complete for HEAD $head: ${run_status:-missing}"
    test "$run_conclusion" = success || die "CI is not green for HEAD $head: ${run_conclusion:-missing}"
    printf 'CI: %s %s\n' "$run_status" "$run_conclusion"
}

check_tag_state() {
    if "$GIT_BIN" -C "$REPO_ROOT" rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
        die "tag already exists locally: $TAG"
    fi
}

check_ci_tag() {
    local current_tag status
    current_tag="${GITHUB_REF_NAME:-}"
    test "$current_tag" = "$TAG" || die "tag $current_tag does not match VERSION tag $TAG"
    status="$("$GIT_BIN" -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
    test -z "$status" || die "CI checkout is not clean"
}

check_checkout_remains_clean() {
    local status
    status="$("$GIT_BIN" -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all)"
    test -z "$status" || die "build or verification changed the checkout"
}

build_app() {
    "$BUILD_BIN"
    test -d "$UNSIGNED_APP" || die "build did not produce $UNSIGNED_APP"
}

stage_app() {
    STAGE_ROOT="$(mktemp -d "$STAGE_PARENT/codexmulti-release.XXXXXX")"
    STAGED_APP="$STAGE_ROOT/CodexMulti.app"
    if test "$RELEASE_MODE" = ci && test -z "${SIGNING_IDENTITY:-}"; then
        "$DITTO_BIN" "$UNSIGNED_APP" "$STAGED_APP"
        SIGNING_STATUS="UNSIGNED"
        printf 'Signing: UNSIGNED because CI signing secrets are unavailable\n'
    else
        CODEXMULTI_USE_EXISTING_BUILD=yes "$PACKAGE_BIN" --stage "$STAGED_APP"
        if test -n "${SIGNING_IDENTITY:-}"; then
            SIGNING_STATUS="DEVELOPER ID"
        else
            SIGNING_STATUS="LOCAL SELF-SIGNED"
        fi
        printf 'Signing: %s\n' "$SIGNING_STATUS"
    fi
}

verify_app() {
    "$PROVENANCE_BIN" "$STAGED_APP"
    "$PROXY_VERIFY_BIN" "$STAGED_APP"
}

notary_credential_count() {
    local count
    count=0
    test -n "${APPLE_NOTARY_KEY_ID:-}" && count=$((count + 1))
    test -n "${APPLE_NOTARY_ISSUER:-}" && count=$((count + 1))
    test -n "${APPLE_NOTARY_KEY_PATH:-}" && count=$((count + 1))
    printf '%s\n' "$count"
}

notarize_app() {
    local credential_count submission_zip
    credential_count="$(notary_credential_count)"
    if test "$credential_count" = 0; then
        NOTARIZATION_STATUS="NOT NOTARIZED"
        printf 'Notarization: NOT NOTARIZED because credentials are unavailable\n'
        return
    fi
    test "$credential_count" = 3 || die "APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER, and APPLE_NOTARY_KEY_PATH must be provided together"
    test "$SIGNING_STATUS" = "DEVELOPER ID" || die "notarization requires Developer ID signing"
    test -f "$APPLE_NOTARY_KEY_PATH" || die "notary key is missing: $APPLE_NOTARY_KEY_PATH"
    submission_zip="$STAGE_ROOT/CodexMulti-notary.zip"
    "$DITTO_BIN" -c -k --keepParent "$STAGED_APP" "$submission_zip"
    "$XCRUN_BIN" notarytool submit "$submission_zip" --key "$APPLE_NOTARY_KEY_PATH" \
        --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER" --wait
    "$XCRUN_BIN" stapler staple "$STAGED_APP"
    "$XCRUN_BIN" stapler validate "$STAGED_APP"
    /bin/rm -f -- "$submission_zip"
    NOTARIZATION_STATUS="NOTARIZED"
    printf 'Notarization: NOTARIZED and stapled\n'
}

package_artifact() {
    local zip_name sha_name
    mkdir -p "$DIST_DIR"
    zip_name="CodexMulti-$VERSION.zip"
    sha_name="$zip_name.sha256"
    ZIP_PATH="$DIST_DIR/$zip_name"
    SHA_PATH="$DIST_DIR/$sha_name"
    /bin/rm -f -- "$ZIP_PATH" "$SHA_PATH"
    "$DITTO_BIN" -c -k --keepParent "$STAGED_APP" "$ZIP_PATH"
    ARTIFACT_SHA256="$("$SHASUM_BIN" -a 256 "$ZIP_PATH" | awk '{print $1}')"
    printf '%s\n' "$ARTIFACT_SHA256" | grep -Eq '^[0-9a-f]{64}$' || die "could not calculate archive SHA-256"
    printf '%s  %s\n' "$ARTIFACT_SHA256" "$zip_name" > "$SHA_PATH"
    printf 'Archive: %s\nChecksum: %s\n' "$ZIP_PATH" "$SHA_PATH"
}

update_cask() {
    local temporary
    test -f "$CASK_FILE" || die "cask is missing: $CASK_FILE"
    temporary="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-cask.XXXXXX")"
    awk -v version="$VERSION" -v sha="$ARTIFACT_SHA256" '
        /^[[:space:]]*version / { print "  version \"" version "\""; version_count++; next }
        /^[[:space:]]*sha256 / { print "  sha256 \"" sha "\""; sha_count++; next }
        { print }
        END { if (version_count != 1 || sha_count != 1) exit 5 }
    ' "$CASK_FILE" > "$temporary" || {
        /bin/rm -f -- "$temporary"
        die "cask must contain exactly one version and sha256 declaration"
    }
    /bin/mv -f "$temporary" "$CASK_FILE"
    printf 'Cask: version %s, sha256 %s\n' "$VERSION" "$ARTIFACT_SHA256"
}

write_release_notes() {
    local extracted
    NOTES_PATH="$DIST_DIR/CodexMulti-$VERSION-release-notes.md"
    extracted="$(mktemp "${TMPDIR:-/private/tmp}/codexmulti-notes.XXXXXX")"
    if ! extract_changelog_section "$VERSION" "$CHANGELOG_FILE" "$extracted"; then
        extract_changelog_section Unreleased "$CHANGELOG_FILE" "$extracted" || {
            /bin/rm -f -- "$extracted"
            die "CHANGELOG has no section for $VERSION and no Unreleased section"
        }
        printf 'Release notes source: CHANGELOG Unreleased section\n'
    else
        printf 'Release notes source: CHANGELOG %s section\n' "$VERSION"
    fi
    {
        printf '# CodexMulti %s\n\n' "$VERSION"
        printf '**Signing: %s**\n\n' "$SIGNING_STATUS"
        printf '**Notarization: %s**\n\n' "$NOTARIZATION_STATUS"
        sed -n '1,$p' "$extracted"
        printf '\n'
    } > "$NOTES_PATH"
    /bin/rm -f -- "$extracted"
    printf 'Release notes: %s\n' "$NOTES_PATH"
}

publish_release() {
    "$GIT_BIN" -C "$REPO_ROOT" tag -a "$TAG" -m "CodexMulti $VERSION"
    "$GIT_BIN" -C "$REPO_ROOT" push origin "refs/tags/$TAG"
    "$GH_BIN" release create "$TAG" "$ZIP_PATH" "$SHA_PATH" --repo "$RELEASE_REPOSITORY" \
        --title "CodexMulti $VERSION" --notes-file "$NOTES_PATH" --verify-tag
}

cleanup_stage() {
    if test -n "$STAGE_ROOT" && test -d "$STAGE_ROOT"; then
        case "$STAGE_ROOT" in
            "$STAGE_PARENT"/codexmulti-release.*) /bin/rm -rf -- "$STAGE_ROOT" ;;
        esac
    fi
}

usage() {
    printf 'Usage: app/scripts/release.sh [--dry-run|--ci]\n' >&2
}

main() {
    test "$#" -le 1 || { usage; exit 2; }
    case "${1:-}" in
        "") RELEASE_MODE=release ;;
        --dry-run) RELEASE_MODE=dry-run ;;
        --ci) RELEASE_MODE=ci ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 2 ;;
    esac
    trap 'fail_stage "$?"' ERR
    trap cleanup_stage EXIT HUP INT TERM

    begin_stage tools
    require_tool "$GIT_BIN"
    require_tool "$DITTO_BIN"
    require_tool "$SHASUM_BIN"
    require_tool "$BUILD_BIN"
    require_tool "$PROVENANCE_BIN"
    require_tool "$PROXY_VERIFY_BIN"
    if test "$RELEASE_MODE" != ci || test -n "${SIGNING_IDENTITY:-}"; then
        require_tool "$PACKAGE_BIN"
    fi
    if test "$RELEASE_MODE" != ci; then
        require_tool "$GH_BIN"
    fi

    begin_stage version
    VERSION="$(read_release_version)"
    TAG="v$VERSION"
    printf 'Version: %s\nTag: %s\n' "$VERSION" "$TAG"

    begin_stage preflight
    if test "$RELEASE_MODE" = ci; then
        check_ci_tag
    else
        check_clean_checkout
        check_ci_success
        check_tag_state
    fi

    begin_stage build
    build_app
    begin_stage signing
    stage_app
    begin_stage verification
    verify_app
    check_checkout_remains_clean
    begin_stage notarization
    notarize_app
    begin_stage packaging
    package_artifact
    begin_stage cask
    update_cask
    begin_stage notes
    write_release_notes

    if test "$RELEASE_MODE" = release; then
        begin_stage publish
        publish_release
        printf 'Release published: %s\n' "$TAG"
    elif test "$RELEASE_MODE" = dry-run; then
        printf 'Dry run complete: artifacts created; no tag was created and nothing was uploaded.\n'
    else
        printf 'CI artifact build complete: tag and release upload are handled by the workflow.\n'
    fi
}

if test "${RELEASE_SOURCE_ONLY:-no}" != yes; then
    main "$@"
fi

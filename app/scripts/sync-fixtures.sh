#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"
REPO_ROOT="$(cd "$PROJECT_DIR/.." && pwd -P)"
CORE_DIR="${CODEXMULTI_CORE_DIR:-$REPO_ROOT/core}"
CORE_DIR="$(cd "$CORE_DIR" && pwd -P)"
case "$CORE_DIR" in
    "$REPO_ROOT"/*) ;;
    *) printf 'error: CORE_DIR must be inside the monorepo: %s\n' "$CORE_DIR" >&2; exit 1 ;;
esac
CORE_RELATIVE="${CORE_DIR#"$REPO_ROOT"/}"
SOURCE_DIR="$CORE_DIR/fixtures/bridge"
DESTINATION_DIR="$PROJECT_DIR/fixtures/bridge"
SOURCE_RECORD="$DESTINATION_DIR/SOURCE"
RSYNC_BIN="${RSYNC_BIN:-/usr/bin/rsync}"
CMP_BIN="${CMP_BIN:-/usr/bin/cmp}"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

test -x "$RSYNC_BIN" || die "required tool is unavailable: $RSYNC_BIN"
test -x "$CMP_BIN" || die "required tool is unavailable: $CMP_BIN"
test -d "$SOURCE_DIR" || die "Lane C fixture directory is missing: $SOURCE_DIR"
source_count="$(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d '[:space:]')"
test "$source_count" -gt 0 || die "Lane C fixture directory contains no JSON fixtures"
source_commit="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$CORE_RELATIVE/fixtures/bridge")"
printf '%s\n' "$source_commit" | grep -Eq '^[0-9a-f]{40}$' || die "cannot resolve the Lane C source commit"




FILTERS=(--exclude='*-PLACEHOLDER-*.json' --include='*.json' --exclude='*')

case "${1:---check}" in
    --sync)
        mkdir -p "$DESTINATION_DIR"
        "$RSYNC_BIN" -a --omit-dir-times --delete "${FILTERS[@]}" \
            "$SOURCE_DIR/" "$DESTINATION_DIR/"
        source_record_tmp="$(mktemp "$DESTINATION_DIR/.SOURCE.XXXXXX")"
        cleanup_source_record() {
            test ! -e "$source_record_tmp" || /bin/rm -f -- "$source_record_tmp"
        }
        trap cleanup_source_record EXIT HUP INT TERM
        printf '%s\n' "$source_commit" > "$source_record_tmp"
        mv "$source_record_tmp" "$SOURCE_RECORD"
        trap - EXIT HUP INT TERM
        printf 'Synced %s bridge JSON fixtures from %s at %s\n' "$source_count" "$SOURCE_DIR" "$source_commit"
        ;;
    --check)
        test -d "$DESTINATION_DIR" || die "Swift fixture directory is missing; run scripts/sync-fixtures.sh --sync"
        test -f "$SOURCE_RECORD" || die "fixture SOURCE record is missing; run scripts/sync-fixtures.sh --sync"
        "$CMP_BIN" -s "$SOURCE_RECORD" <(printf '%s\n' "$source_commit") ||
            die "fixture SOURCE does not exactly match Lane C commit $source_commit"


        changes="$($RSYNC_BIN -rnc --delete -v "${FILTERS[@]}" "$SOURCE_DIR/" "$DESTINATION_DIR/" |
            grep -E '^(deleting )?[^ ]+[.]json$' || true)"
        test -z "$changes" || {
            printf '%s\n' "$changes" >&2
            die "Swift bridge JSON fixtures differ; run scripts/sync-fixtures.sh --sync"
        }
        printf 'Bridge JSON fixtures match Lane C: %s files at %s\n' "$source_count" "$source_commit"
        ;;
    *)
        printf 'Usage: scripts/sync-fixtures.sh [--sync|--check]\n' >&2
        exit 2
        ;;
esac

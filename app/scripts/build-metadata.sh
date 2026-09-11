#!/bin/bash

DATE_BIN="${DATE_BIN:-/bin/date}"

build_metadata_die() {
    printf 'error: %s\n' "$*" >&2
    return 1
}

resolve_build_metadata() {
    local version_line_count
    VERSION_FILE="${VERSION_FILE:-$REPO_ROOT/VERSION}"
    test -f "$VERSION_FILE" || build_metadata_die "VERSION file is missing: $VERSION_FILE" || return
    version_line_count="$(awk 'END { print NR + 0 }' "$VERSION_FILE")"
    test "$version_line_count" = "1" || build_metadata_die "VERSION must contain exactly one line: $VERSION_FILE" || return
    APP_VERSION="$(sed -n '1p' "$VERSION_FILE")"
    printf '%s\n' "$APP_VERSION" | grep -Eq '^[0-9]+[.][0-9]+[.][0-9]+([+-][0-9A-Za-z.-]+)?$' ||
        build_metadata_die "invalid app version in $VERSION_FILE: $APP_VERSION" || return
    BUILD_NUMBER="$("$DATE_BIN" -u +%Y%m%d%H%M)" ||
        build_metadata_die "could not calculate the UTC build number" || return
    printf '%s\n' "$BUILD_NUMBER" | grep -Eq '^[0-9]{12}$' ||
        build_metadata_die "invalid UTC build number: $BUILD_NUMBER" || return
}

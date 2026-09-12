#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RELEASE_SCRIPT="$SCRIPT_DIR/../release.sh"
temp_root="$(mktemp -d "${TMPDIR:-/private/tmp}/codexmulti-release-test.XXXXXX")"

cleanup() {
    case "$temp_root" in
        "${TMPDIR:-/private/tmp}"/codexmulti-release-test.*) /bin/rm -rf -- "$temp_root" ;;
    esac
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$temp_root/repo/homebrew/Casks" "$temp_root/repo/app/dist/staging" "$temp_root/bin" "$temp_root/tmp" "$temp_root/output"
printf '0.2.0\n' > "$temp_root/repo/VERSION"
printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- Release pipeline.\n' > "$temp_root/repo/CHANGELOG.md"
printf '# Changelog\n\n## [0.2.0]\n\n### Added\n\n- Release pipeline.\n\n## [0.1.0]\n\n- Older.\n' > "$temp_root/versioned-changelog.md"
printf 'cask "codexmulti" do\n  version "RELEASE_VERSION"\n  sha256 "RELEASE_SHA256"\nend\n' > "$temp_root/repo/homebrew/Casks/codexmulti.rb"

RELEASE_SOURCE_ONLY=yes
RELEASE_REPO_ROOT="$temp_root/repo"
VERSION_FILE="$temp_root/repo/VERSION"
CHANGELOG_FILE="$temp_root/repo/CHANGELOG.md"
CASK_FILE="$temp_root/repo/homebrew/Casks/codexmulti.rb"
RELEASE_DIST_DIR="$temp_root/output"
. "$RELEASE_SCRIPT"

test "$(read_release_version)" = "0.2.0" || {
    printf 'FAIL release version extraction\n' >&2
    exit 1
}
extract_changelog_section 0.2.0 "$temp_root/versioned-changelog.md" "$temp_root/extracted.md"
grep -F -x -- '### Added' "$temp_root/extracted.md" >/dev/null || {
    printf 'FAIL release notes omitted the selected section\n' >&2
    exit 1
}
if grep -F -- 'Older.' "$temp_root/extracted.md" >/dev/null; then
    printf 'FAIL release notes crossed into the next section\n' >&2
    exit 1
fi

printf '#!/bin/bash\nset -euo pipefail\ncase " $* " in\n  *" status "*) exit 0 ;;\n  *" branch --show-current "*) printf "main\\n" ;;\n  *" rev-parse HEAD "*) printf "deadbeef\\n" ;;\n  *" rev-parse --verify --quiet "*) exit 1 ;;\n  *" tag "*|*" push "*) printf "%%s\\n" "$*" >> "$RELEASE_TEST_LOG" ;;\n  *) exit 1 ;;\nesac\n' > "$temp_root/bin/git"
printf '#!/bin/bash\nset -euo pipefail\ncase " $* " in\n  *" run list "*) printf "deadbeef\\tcompleted\\tsuccess\\n" ;;\n  *" release "*) printf "%%s\\n" "$*" >> "$RELEASE_TEST_LOG" ;;\n  *) exit 1 ;;\nesac\n' > "$temp_root/bin/gh"
printf '#!/bin/bash\nset -euo pipefail\nmkdir -p "$RELEASE_TEST_REPO/app/dist/staging/CodexMulti.app/Contents/MacOS"\nprintf "fixture\\n" > "$RELEASE_TEST_REPO/app/dist/staging/CodexMulti.app/Contents/MacOS/CodexMulti"\nchmod 755 "$RELEASE_TEST_REPO/app/dist/staging/CodexMulti.app/Contents/MacOS/CodexMulti"\n' > "$temp_root/bin/build"
printf '#!/bin/bash\nset -euo pipefail\neval "output=\\${$#}"\ncp -R "$RELEASE_TEST_REPO/app/dist/staging/CodexMulti.app" "$output"\n' > "$temp_root/bin/package"
printf '#!/bin/bash\nset -euo pipefail\ntest -d "$1"\n' > "$temp_root/bin/verify"
chmod 755 "$temp_root/bin/git" "$temp_root/bin/gh" "$temp_root/bin/build" "$temp_root/bin/package" "$temp_root/bin/verify"
: > "$temp_root/release.log"

TMPDIR="$temp_root/tmp" \
RELEASE_REPO_ROOT="$temp_root/repo" \
VERSION_FILE="$temp_root/repo/VERSION" \
CHANGELOG_FILE="$temp_root/repo/CHANGELOG.md" \
CASK_FILE="$temp_root/repo/homebrew/Casks/codexmulti.rb" \
RELEASE_DIST_DIR="$temp_root/output" \
UNSIGNED_APP="$temp_root/repo/app/dist/staging/CodexMulti.app" \
BUILD_BIN="$temp_root/bin/build" \
PACKAGE_BIN="$temp_root/bin/package" \
PROVENANCE_BIN="$temp_root/bin/verify" \
PROXY_VERIFY_BIN="$temp_root/bin/verify" \
STARTUP_VERIFY_BIN="$temp_root/bin/verify" \
GIT_BIN="$temp_root/bin/git" \
GH_BIN="$temp_root/bin/gh" \
DITTO_BIN="/usr/bin/ditto" \
RELEASE_TEST_REPO="$temp_root/repo" \
RELEASE_TEST_LOG="$temp_root/release.log" \
"$RELEASE_SCRIPT" --dry-run

test -s "$temp_root/output/CodexMulti-0.2.0.zip" || {
    printf 'FAIL dry run did not create the zip\n' >&2
    exit 1
}
/usr/bin/unzip -t "$temp_root/output/CodexMulti-0.2.0.zip" >/dev/null || {
    printf 'FAIL dry run did not create a valid zip\n' >&2
    exit 1
}
test -s "$temp_root/output/CodexMulti-0.2.0.zip.sha256" || {
    printf 'FAIL dry run did not create the checksum\n' >&2
    exit 1
}
grep -F -x -- '**Notarization: NOT NOTARIZED**' "$temp_root/output/CodexMulti-0.2.0-release-notes.md" >/dev/null || {
    printf 'FAIL dry run notes did not disclose notarization status\n' >&2
    exit 1
}
grep -F -x -- '  version "0.2.0"' "$temp_root/repo/homebrew/Casks/codexmulti.rb" >/dev/null || {
    printf 'FAIL dry run did not update the cask version\n' >&2
    exit 1
}
grep -Eq '^  sha256 "[0-9a-f]{64}"$' "$temp_root/repo/homebrew/Casks/codexmulti.rb" || {
    printf 'FAIL dry run did not update the cask checksum\n' >&2
    exit 1
}
test ! -s "$temp_root/release.log" || {
    printf 'FAIL dry run created a tag or uploaded a release\n' >&2
    exit 1
}

printf 'PASS release version extraction, notes extraction, and dry-run artifact path\n'

# Credential omission must fail before any public build or upload, including CI.
for mode in release ci; do
    if (RELEASE_MODE="$mode"; unset SIGNING_IDENTITY APPLE_NOTARY_KEY_ID APPLE_NOTARY_ISSUER APPLE_NOTARY_KEY_PATH; check_distribution_credentials) >"$temp_root/credential-check.log" 2>&1; then
        printf 'FAIL public release accepted missing credentials in %s mode\n' "$mode" >&2
        exit 1
    fi
done
if (RELEASE_MODE=ci; SIGNING_IDENTITY=fixture; APPLE_NOTARY_KEY_ID=fixture; unset APPLE_NOTARY_ISSUER APPLE_NOTARY_KEY_PATH; check_distribution_credentials) >"$temp_root/credential-check.log" 2>&1; then
    printf 'FAIL public release accepted partial notarization credentials\n' >&2
    exit 1
fi
printf 'PASS public release and CI fail closed without signing and notarization\n'

if (SIGNING_STATUS="DEVELOPER ID"; STAGED_APP="$temp_root/repo/app/dist/staging/CodexMulti.app"; PROVENANCE_BIN="$temp_root/bin/verify"; PROXY_VERIFY_BIN="$temp_root/bin/verify"; STARTUP_VERIFY_BIN=/usr/bin/false; verify_app) >"$temp_root/startup-check.log" 2>&1; then
    printf 'FAIL public verification accepted a failed signed-app startup\n' >&2
    exit 1
fi
printf 'PASS public verification requires real signed-app startup\n'

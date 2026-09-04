#!/bin/sh
# check-versions.sh — one version, declared in four places, must agree.
#
# The four:
#   package.json                     "version"
#   skills/holochain/SKILL.md        frontmatter metadata.version
#   CHANGELOG.md                     the topmost "## [x.y.z]" heading
#   the git tag                      passed as $1, with or without a leading v
#
# Nothing here is cosmetic. A published npm package whose SKILL.md declares a
# different version tells a consumer they have something they do not, and there
# is no way to notice from inside an installed skill. CI runs this on every PR
# without a tag, and again at release time with the tag, before anything is
# published.
#
# Usage:
#   scripts/check-versions.sh            compare the three in-tree declarations
#   scripts/check-versions.sh v1.0.0     also require the tag to match
#
# POSIX sh, coreutils/grep/sed only, matching the other scripts here.

set -u

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT" || exit 2

SKILL_MD="skills/holochain/SKILL.md"
FAILURES=0

fail() {
    printf 'FAIL  %s\n' "$1"
    FAILURES=$((FAILURES + 1))
}

PKG_VERSION=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)
[ -n "$PKG_VERSION" ] || { fail "package.json declares no version"; }

# metadata.version sits inside the frontmatter's metadata block, so take the
# first `version:` that appears before the closing fence.
SKILL_VERSION=$(sed -n '2,/^---$/p' "$SKILL_MD" 2>/dev/null \
    | sed -n 's/^[[:space:]]*version:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' | head -n 1)
[ -n "$SKILL_VERSION" ] || { fail "$SKILL_MD declares no metadata.version"; }

CHANGELOG_VERSION=$(sed -n 's/^## \[\([0-9][^]]*\)\].*/\1/p' CHANGELOG.md | head -n 1)
[ -n "$CHANGELOG_VERSION" ] || { fail "CHANGELOG.md has no versioned heading"; }

printf '%-26s%s\n' 'package.json' "${PKG_VERSION:-<none>}"
printf '%-26s%s\n' "$SKILL_MD" "${SKILL_VERSION:-<none>}"
printf '%-26s%s\n' 'CHANGELOG.md' "${CHANGELOG_VERSION:-<none>}"

[ "$PKG_VERSION" = "$SKILL_VERSION" ] \
    || fail "package.json ($PKG_VERSION) and $SKILL_MD ($SKILL_VERSION) disagree"
[ "$PKG_VERSION" = "$CHANGELOG_VERSION" ] \
    || fail "package.json ($PKG_VERSION) and CHANGELOG.md ($CHANGELOG_VERSION) disagree"

if [ "$#" -ge 1 ] && [ -n "$1" ]; then
    TAG_VERSION=${1#v}
    printf '%-26s%s\n' 'git tag' "$1"
    [ "$PKG_VERSION" = "$TAG_VERSION" ] \
        || fail "tag $1 and package.json ($PKG_VERSION) disagree"

    # A release whose changelog has no section for the tag ships with an empty
    # GitHub release body, because release.yml extracts the body from exactly
    # that heading.
    grep -q "^## \[$TAG_VERSION\]" CHANGELOG.md \
        || fail "CHANGELOG.md has no '## [$TAG_VERSION]' section for tag $1"
fi

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'PASS: all version declarations agree.\n'
    exit 0
fi
printf 'FAILED: %d check(s).\n' "$FAILURES"
exit 1

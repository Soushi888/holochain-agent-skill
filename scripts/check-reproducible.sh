#!/bin/sh
# check-reproducible.sh — assert that the release archives depend only on the
# commit, not on when or where they were built.
#
# A consumer can pin a checksum of these archives in a Nix expression. If a
# rebuild of the same commit produces different bytes, that pin breaks for no
# reason the consumer can see.
#
# WHY THIS ASSERTS RATHER THAN COMPARES. The obvious check is to build twice and
# diff the checksums. That check is timing-dependent and therefore worse than no
# check: zip records a DOS timestamp with two-second granularity, so two builds
# run back to back land in the same window and produce identical digests even
# when the stamping is broken. Measured: with the mtime normalisation deliberately
# removed, build-twice-and-compare PASSED. A gate that only fails when the
# machine happens to be slow reads as coverage while providing none.
#
# So this asserts the property directly: every member of every archive must
# carry the fixed epoch, not a build-time timestamp. That is deterministic, and
# it fails immediately on the exact regression above.
#
# Usage: scripts/check-reproducible.sh   (run after scripts/build-release-assets.sh)

set -u

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT" || exit 2

DIST="$REPO_ROOT/dist"
[ -d "$DIST" ] || { echo "error: no dist/. Run scripts/build-release-assets.sh first." >&2; exit 2; }

FAILURES=0

# The staging tree is stamped to 2020-01-01 UTC. Archive listings render that in
# local time, so the date shown is either 2020-01-01 or 2019-12-31 depending on
# the runner's zone. Either is fine; what matters is that there is exactly ONE
# distinct date, because a build-time stamp produces today's.
check_dates() {
    kind=$1
    dates=$2
    count=$(printf '%s\n' "$dates" | grep -c . || true)

    if [ -z "$dates" ] || [ "$count" -eq 0 ]; then
        printf 'FAIL  [%s] no member timestamps could be read\n' "$kind"
        FAILURES=$((FAILURES + 1))
        return
    fi

    if [ "$count" -ne 1 ]; then
        printf 'FAIL  [%s] members carry %s distinct dates, expected 1:\n' "$kind" "$count"
        printf '%s\n' "$dates" | sed 's/^/        /'
        printf '        a build-time timestamp leaked in; see scripts/build-release-assets.sh\n'
        FAILURES=$((FAILURES + 1))
        return
    fi

    case "$dates" in
        2020-01-01|2019-12-31|2019-12-3[01])
            printf 'ok    [%s] every member carries %s\n' "$kind" "$dates"
            ;;
        *)
            printf 'FAIL  [%s] members carry %s, not the fixed epoch\n' "$kind" "$dates"
            FAILURES=$((FAILURES + 1))
            ;;
    esac
}

ZIP=$(ls "$DIST"/holochain-agent-skills-*.zip 2>/dev/null | head -n 1)
TAR=$(ls "$DIST"/holochain-agent-skills-*.tar.gz 2>/dev/null | head -n 1)

[ -n "$ZIP" ] || { echo "FAIL  [zip] no versioned zip in dist/"; FAILURES=$((FAILURES + 1)); }
[ -n "$TAR" ] || { echo "FAIL  [tar] no versioned tarball in dist/"; FAILURES=$((FAILURES + 1)); }

if [ -n "$ZIP" ]; then
    check_dates zip "$(unzip -l "$ZIP" | awk 'NR>3 && NF>=4 {print $2}' \
        | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -u)"
fi

if [ -n "$TAR" ]; then
    check_dates tar "$(tar -tvzf "$TAR" | awk '{print $4}' \
        | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -u)"
fi

# The unversioned copy backing releases/latest/download must be byte-identical
# to the versioned tarball, or the two URLs hand out different trees.
LATEST="$DIST/holochain-agent-skills.tar.gz"
if [ -n "$TAR" ] && [ -f "$LATEST" ]; then
    if cmp -s "$TAR" "$LATEST"; then
        printf 'ok    [latest] the unversioned copy is byte-identical to %s\n' "$(basename "$TAR")"
    else
        printf 'FAIL  [latest] holochain-agent-skills.tar.gz differs from %s\n' "$(basename "$TAR")"
        FAILURES=$((FAILURES + 1))
    fi
fi

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'PASS: archives depend only on the commit.\n'
    exit 0
fi
printf 'FAILED: %d check(s).\n' "$FAILURES"
exit 1

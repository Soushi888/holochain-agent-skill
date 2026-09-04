#!/bin/sh
# build-release-assets.sh — build the GitHub release archives.
#
# Produces, under dist/:
#   holochain-agent-skills-<version>.tar.gz
#   holochain-agent-skills-<version>.zip
#   holochain-agent-skills.tar.gz            (a copy, for the stable
#                                             releases/latest/download URL)
#   SHA256SUMS
#
# ARCHIVE SHAPE, and why it matters: each archive holds one directory per
# skill AT ITS ROOT, so
#
#   tar -xzf holochain-agent-skills.tar.gz -C .claude/skills
#
# lands `.claude/skills/holochain/SKILL.md` in one command with no rename step.
# An archive rooted at a versioned directory would need a --strip-components
# dance that people get wrong, and the whole point of the curl fallback is that
# it is one line someone can paste.
#
# Reproducibility: files are staged from `git archive` (tracked content only,
# so no stray build output), and both archives are written with a fixed
# timestamp and sorted member order so the same commit produces the same
# checksum twice.
#
# Usage: scripts/build-release-assets.sh [version]
#        version defaults to package.json's.

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT"

VERSION=${1:-$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -n 1)}
[ -n "$VERSION" ] || { echo "error: no version given and none in package.json" >&2; exit 2; }

DIST="$REPO_ROOT/dist"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT INT TERM

rm -rf "$DIST"
mkdir -p "$DIST" "$STAGE/payload"

# Tracked content only. A working tree can hold an untracked Rust target/ or a
# node_modules/, and neither belongs in a release archive.
git archive --format=tar HEAD skills | tar -x -C "$STAGE"

for skill in "$STAGE"/skills/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    [ -f "$skill/SKILL.md" ] || { echo "error: $name has no SKILL.md" >&2; exit 1; }
    cp -r "$skill" "$STAGE/payload/$name"
done

[ -n "$(ls -A "$STAGE/payload")" ] || { echo "error: no skills staged" >&2; exit 1; }

# `git archive` carries no mtimes, so extraction stamps every file with the
# current time. tar can override that with --mtime; zip cannot, because it
# writes a DOS timestamp per member from the filesystem. Without this the zip's
# checksum changes on every build of the same commit. Measured: two builds of
# an unchanged tree produced two different zip digests before this line.
TZ=UTC find "$STAGE/payload" -exec touch -t 202001010000.00 {} +

TARBALL="$DIST/holochain-agent-skills-$VERSION.tar.gz"
ZIPFILE="$DIST/holochain-agent-skills-$VERSION.zip"

# --sort=name and a fixed mtime make the tarball byte-identical across runs of
# the same commit, so a checksum published in a Nix expression stays valid.
tar --sort=name \
    --mtime='UTC 2020-01-01' \
    --owner=0 --group=0 --numeric-owner \
    -czf "$TARBALL" \
    -C "$STAGE/payload" .

( cd "$STAGE/payload" && find . -type f | LC_ALL=C sort | zip -q -X "$ZIPFILE" -@ )

cp "$TARBALL" "$DIST/holochain-agent-skills.tar.gz"

( cd "$DIST" && sha256sum ./*.tar.gz ./*.zip | sed 's|\./||' > SHA256SUMS )

echo "Built for $VERSION:"
ls -la "$DIST"
echo
cat "$DIST/SHA256SUMS"

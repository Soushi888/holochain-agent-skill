#!/bin/sh
# bump-versions.sh — rewrite Holochain toolchain version pins across the skill.
#
# Replaces the manual grep-and-edit procedure. POSIX sh; coreutils, grep and sed only.
#
# Usage:
#   scripts/bump-versions.sh --hdk 0.7.0 --hdi 0.8.0 --holonix main-0.7 \
#                            [--node 24] [--client 0.21.0] [--hc-spin 0.700.0] [--dry-run]
#
# IMPORTANT: bumping pins is NOT the same as making content correct. Holochain
# minor releases carry breaking API changes, so after running this you MUST run
# scripts/validate-skill.sh, which fails on APIs removed in the target version.
# A green bump with a red validator means the skill claims a version it does not teach.

set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT" || exit 2

HDK=""; HDI=""; HOLONIX=""; NODE=""; CLIENT=""; HC_SPIN=""; DRY_RUN=0

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-1}"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --hdk)     HDK="${2:?--hdk needs a value}"; shift 2 ;;
        --hdi)     HDI="${2:?--hdi needs a value}"; shift 2 ;;
        --holonix) HOLONIX="${2:?--holonix needs a value}"; shift 2 ;;
        --node)    NODE="${2:?--node needs a value}"; shift 2 ;;
        --client)  CLIENT="${2:?--client needs a value}"; shift 2 ;;
        --hc-spin) HC_SPIN="${2:?--hc-spin needs a value}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage 0 ;;
        *) printf 'unknown argument: %s\n\n' "$1" >&2; usage 1 ;;
    esac
done

[ -n "$HDK" ] && [ -n "$HDI" ] && [ -n "$HOLONIX" ] || {
    printf 'error: --hdk, --hdi and --holonix are all required\n\n' >&2
    usage 1
}

# Files eligible for rewriting: skill content and templates, never build output,
# private working directories, or the changelog (which records history verbatim).
FILES=$(find . \( -name '*.md' -o -name '*.nix' -o -name '*.toml' -o -name '*.json' \
                 -o -name '*.yaml' -o -name '*.yml' \) -type f \
    ! -path './book/*' ! -path './MEMORY/*' ! -path './Plans/*' \
    ! -path './.local/*' ! -path './.git/*' ! -path './node_modules/*' \
    ! -path './.worktrees/*' \
    ! -path './CHANGELOG.md' | sed 's|^\./||' | sort)

BEFORE=$(mktemp) || exit 2
AFTER=$(mktemp) || exit 2
trap 'rm -f "$BEFORE" "$AFTER"' EXIT INT TERM

# `sed -i` is a GNU extension and is NOT POSIX. BSD and macOS sed read the next
# argument as a backup suffix, so `sed -i -e ...` there treats `-e` as the suffix
# and mangles every file the script touches. Edit through a temp file instead,
# which behaves identically on both.
sed_inplace() {
    # sed_inplace <file> <sed-args...>
    _f="$1"; shift
    sed "$@" "$_f" > "$_f.bump.tmp" && mv "$_f.bump.tmp" "$_f"
}

apply() {
    # apply <file>: rewrite every pin form
    f="$1"
    sed_inplace "$f" \
        -e "s|hdk = \"=[0-9][0-9.]*\"|hdk = \"=$HDK\"|g" \
        -e "s|hdi = \"=[0-9][0-9.]*\"|hdi = \"=$HDI\"|g" \
        -e "s|hdk=[0-9][0-9.]*|hdk=$HDK|g" \
        -e "s|hdi=[0-9][0-9.]*|hdi=$HDI|g" \
        -e "s|holonix?ref=main-[0-9.]*|holonix?ref=$HOLONIX|g" \
        -e "s|holonix ref=main-[0-9.]*|holonix ref=$HOLONIX|g"
    [ -n "$NODE" ]    && sed_inplace "$f" -e "s|nodejs_[0-9][0-9]*|nodejs_$NODE|g"
    [ -n "$CLIENT" ]  && sed_inplace "$f" \
        -e "s|\(\"@holochain/client\": \"\^\)[0-9][0-9.]*|\1$CLIENT|g" \
        -e "s|@holochain/client   \^[0-9][0-9.x]*|@holochain/client   ^$CLIENT|g"
    [ -n "$HC_SPIN" ] && sed_inplace "$f" -e "s|\(\"@holochain/hc-spin\": \"\^\)[0-9][0-9.]*|\1$HC_SPIN|g"
    return 0
}

printf 'Bumping to: hdk=%s hdi=%s holonix=%s' "$HDK" "$HDI" "$HOLONIX"
[ -n "$NODE" ]    && printf ' node=%s' "$NODE"
[ -n "$CLIENT" ]  && printf ' client=%s' "$CLIENT"
[ -n "$HC_SPIN" ] && printf ' hc-spin=%s' "$HC_SPIN"
printf '\n\n'

CHANGED=0
for f in $FILES; do
    [ -f "$f" ] || continue
    cp "$f" "$BEFORE"
    cp "$f" "$AFTER"
    ( f="$AFTER"; apply "$AFTER" )
    if ! cmp -s "$BEFORE" "$AFTER"; then
        n=$(diff "$BEFORE" "$AFTER" | grep -c '^>' || true)
        printf '  %-46s %s line(s)\n' "$f" "$n"
        CHANGED=$((CHANGED + 1))
        [ "$DRY_RUN" -eq 0 ] && cp "$AFTER" "$f"
    fi
done

printf '\n'
if [ "$DRY_RUN" -eq 1 ]; then
    printf 'DRY RUN: %d file(s) would change. Nothing written.\n' "$CHANGED"
else
    printf '%d file(s) rewritten.\n' "$CHANGED"
fi

cat <<'EOF'

Next step is mandatory, not optional:

    scripts/validate-skill.sh

Pins and prose are different things. This script moved the pins. The validator is
what proves the skill does not still teach the previous version's API.
EOF

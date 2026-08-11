#!/bin/sh
# validate-skill.sh — structural and currency validator for the Holochain agent skill.
#
# POSIX sh. Depends only on coreutils, grep and sed, so it runs identically in CI
# and inside `nix develop`. Exits non-zero if any check fails.
#
# Usage: scripts/validate-skill.sh [-v]
#   -v  verbose: also print each passing check

set -u

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT" || exit 2

VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

FAILURES=0
TMPDIR_=$(mktemp -d) || exit 2
trap 'rm -rf "$TMPDIR_"' EXIT INT TERM

fail() {
    printf 'FAIL  [%s] %s\n' "$1" "$2"
    FAILURES=$((FAILURES + 1))
}
pass() {
    [ "$VERBOSE" -eq 1 ] && printf 'ok    [%s] %s\n' "$1" "$2"
    return 0
}
section() {
    printf '\n== %s ==\n' "$1"
}

# ---------------------------------------------------------------------------
# File inventory. Skill content only: excludes build output, private working
# directories, and the project's own tracking docs where noted.
# ---------------------------------------------------------------------------

ALL_MD="$TMPDIR_/all_md"
find . -name '*.md' -type f \
    ! -path './book/*' \
    ! -path './MEMORY/*' \
    ! -path './Plans/*' \
    ! -path './.local/*' \
    ! -path './.git/*' \
    ! -path './node_modules/*' \
    ! -path './assets/*' \
    ! -path './references/example-happ/*' \
    | sed 's|^\./||' | sort > "$ALL_MD"

# ---------------------------------------------------------------------------
# 1. Frontmatter
# ---------------------------------------------------------------------------
section "Frontmatter (SKILL.md)"

if [ ! -f SKILL.md ]; then
    fail frontmatter "SKILL.md is missing"
else
    if [ "$(head -n 1 SKILL.md)" != "---" ]; then
        fail frontmatter "SKILL.md does not begin with a --- frontmatter fence"
    else
        FM="$TMPDIR_/frontmatter"
        sed -n '2,/^---$/p' SKILL.md | sed '$d' > "$FM"

        SKILL_NAME=$(sed -n 's/^name:[[:space:]]*//p' "$FM" | head -n 1)
        if [ -z "$SKILL_NAME" ]; then
            fail frontmatter "no 'name:' field"
        elif ! printf '%s' "$SKILL_NAME" | grep -Eq '^[a-z0-9-]+$'; then
            fail frontmatter "name '$SKILL_NAME' does not match ^[a-z0-9-]+\$"
        else
            pass frontmatter "name '$SKILL_NAME' is well-formed"
        fi

        # description may be a folded block scalar; take everything from
        # 'description:' up to the next top-level key.
        DESC=$(sed -n '/^description:/,/^[a-z_-]*:/p' "$FM" \
            | sed '1s/^description:[[:space:]]*>*[[:space:]]*//' \
            | sed '$ { /^[a-z_-]*:/d; }' | tr -d '\n')
        DESC_LEN=$(printf '%s' "$DESC" | wc -c | tr -d ' ')
        if [ -z "$DESC" ]; then
            fail frontmatter "no 'description:' field"
        elif [ "$DESC_LEN" -gt 1024 ]; then
            fail frontmatter "description is $DESC_LEN chars, limit is 1024"
        else
            pass frontmatter "description is $DESC_LEN chars"
        fi

        for field in license metadata; do
            grep -q "^${field}:" "$FM" || fail frontmatter "no '${field}:' field"
        done
    fi
fi

# ---------------------------------------------------------------------------
# 2. Routing targets resolve
#    Every backticked *.md path and every markdown link target named in
#    SKILL.md must exist on disk.
# ---------------------------------------------------------------------------
section "Routing targets resolve"

ROUTED="$TMPDIR_/routed"
: > "$ROUTED"
if [ -f SKILL.md ]; then
    grep -o '`[A-Za-z0-9_/.-]*\.md`' SKILL.md | tr -d '`' >> "$ROUTED"
    grep -o '](\([A-Za-z0-9_/.-]*\.md\))' SKILL.md | sed 's/^](//; s/)$//' >> "$ROUTED"
fi
sort -u "$ROUTED" -o "$ROUTED"

while IFS= read -r target; do
    [ -z "$target" ] && continue
    if [ -f "$target" ]; then
        pass routing "$target"
    else
        fail routing "SKILL.md routes to '$target' which does not exist"
    fi
done < "$ROUTED"

# ---------------------------------------------------------------------------
# 3. Orphan detection
#    Every skill markdown file must be reachable from SKILL.md or SUMMARY.md.
# ---------------------------------------------------------------------------
section "Orphan detection"

REACHABLE="$TMPDIR_/reachable"
cat "$ROUTED" > "$REACHABLE"
if [ -f SUMMARY.md ]; then
    grep -o '](\([A-Za-z0-9_/.-]*\.md\))' SUMMARY.md | sed 's/^](//; s/)$//' >> "$REACHABLE"
fi
# Entry points and community files are reachable by definition.
for f in SKILL.md SUMMARY.md README.md CLAUDE.md CHANGELOG.md CONTRIBUTING.md \
         CODE_OF_CONDUCT.md; do
    printf '%s\n' "$f" >> "$REACHABLE"
done
# GitHub templates are consumed by GitHub, not by routing.
grep '^\.github/' "$ALL_MD" >> "$REACHABLE" 2>/dev/null
sort -u "$REACHABLE" -o "$REACHABLE"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    if grep -qxF "$f" "$REACHABLE"; then
        pass orphan "$f is reachable"
    else
        fail orphan "'$f' is not reachable from SKILL.md or SUMMARY.md"
    fi
done < "$ALL_MD"

# ---------------------------------------------------------------------------
# 4. Relative markdown links resolve
# ---------------------------------------------------------------------------
section "Relative link resolution"

while IFS= read -r f; do
    [ -z "$f" ] && continue
    dir=$(dirname "$f")
    grep -o '](\([A-Za-z0-9_./-]*\.md\)\(#[A-Za-z0-9_-]*\)\?)' "$f" 2>/dev/null \
        | sed 's/^](//; s/)$//; s/#.*$//' \
        | while IFS= read -r link; do
            [ -z "$link" ] && continue
            case "$link" in
                /*) resolved="${link#/}" ;;
                *)  if [ "$dir" = "." ]; then resolved="$link"; else resolved="$dir/$link"; fi ;;
            esac
            # normalise ../ segments
            resolved=$(printf '%s' "$resolved" | sed ':a; s|[^/][^/]*/\.\./||; ta; s|^\./||')
            if [ ! -f "$resolved" ]; then
                printf 'FAIL  [links] %s -> %s (unresolved)\n' "$f" "$link"
            fi
        done
done < "$ALL_MD" > "$TMPDIR_/linkfails"

if [ -s "$TMPDIR_/linkfails" ]; then
    cat "$TMPDIR_/linkfails"
    FAILURES=$((FAILURES + $(wc -l < "$TMPDIR_/linkfails" | tr -d ' ')))
else
    pass links "all relative markdown links resolve"
fi

# ---------------------------------------------------------------------------
# 5. Version pin consistency
#    The pins declared in SKILL.md frontmatter are authoritative; no file may
#    contradict them, and no superseded pin may survive anywhere.
# ---------------------------------------------------------------------------
section "Version pin consistency"

EXPECT_HDK="0.7.0"
EXPECT_HDI="0.8.0"
EXPECT_HOLONIX="main-0.7"
EXPECT_NODE="nodejs_24"
EXPECT_CLIENT="0.21"

if [ -f SKILL.md ]; then
    DECLARED=$(sed -n 's/.*holochain-versions:[[:space:]]*"\{0,1\}\(.*\)/\1/p' SKILL.md | head -n 1)
    case "$DECLARED" in
        *"hdk=$EXPECT_HDK"*) pass pins "frontmatter declares hdk=$EXPECT_HDK" ;;
        *) fail pins "SKILL.md frontmatter does not declare hdk=$EXPECT_HDK (got: ${DECLARED:-none})" ;;
    esac
    case "$DECLARED" in
        *"hdi=$EXPECT_HDI"*) pass pins "frontmatter declares hdi=$EXPECT_HDI" ;;
        *) fail pins "SKILL.md frontmatter does not declare hdi=$EXPECT_HDI (got: ${DECLARED:-none})" ;;
    esac
fi

check_absent() {
    # check_absent <label> <pattern> <explanation>
    # NOTE: no `--` before the pattern. It terminates option parsing, which
    # would turn every --exclude-dir that follows into a file argument.
    hits=$(grep -rn --include='*.md' --include='*.nix' --include='*.toml' \
        --include='*.json' --include='*.yaml' --include='*.yml' \
        --exclude-dir=book --exclude-dir=MEMORY --exclude-dir=Plans \
        --exclude-dir=.local --exclude-dir=.git --exclude-dir=node_modules \
        --exclude-dir=assets \
        "$2" . 2>/dev/null)
    if [ -n "$hits" ]; then
        printf 'FAIL  [%s] %s\n' "$1" "$3"
        printf '%s\n' "$hits" | sed 's/^/        /'
        FAILURES=$((FAILURES + 1))
    else
        pass "$1" "$3"
    fi
}

check_absent pins 'hdk = "=0\.6' 'no superseded hdk 0.6.x pin'
check_absent pins 'hdi = "=0\.7' 'no superseded hdi 0.7.x pin'
check_absent pins 'ref=main-0\.6' 'no superseded holonix main-0.6 ref'
check_absent pins 'nodejs_22' 'no superseded nodejs_22'
check_absent pins '@holochain/client": "\^0\.20' 'no superseded @holochain/client 0.20.x'

# ---------------------------------------------------------------------------
# 6. APIs removed in Holochain 0.7 must not appear
#    This is the check that stops a pin bump from producing a skill that claims
#    0.7 while teaching 0.6.
# ---------------------------------------------------------------------------
section "Holochain 0.7 forbidden APIs"

check_absent api07 'EntryCreationAction'      'EntryCreationAction (0.7: TypedAction<EntryCreationData>)'
check_absent api07 'FlatOp::StoreEntry'       'FlatOp::StoreEntry (0.7: FlatOp::CreateEntry)'
check_absent api07 'FlatOp::StoreRecord'      'FlatOp::StoreRecord (0.7: FlatOp::CreateRecord)'
check_absent api07 'RegisterUpdate'           'FlatOp::RegisterUpdate (0.7: FlatOp::Update)'
check_absent api07 'RegisterDelete'           'FlatOp::RegisterDelete (0.7: FlatOp::Delete)'
check_absent api07 'RegisterCreateLink'       'FlatOp::RegisterCreateLink (0.7: FlatOp::Link)'
check_absent api07 'RegisterDeleteLink'       'FlatOp::RegisterDeleteLink (0.7: FlatOp::Link)'
check_absent api07 'RegisterAgentActivity'    'FlatOp::RegisterAgentActivity (0.7: FlatOp::AgentActivity)'
check_absent api07 'NewEntryAction'           'NewEntryAction (removed in 0.7)'
check_absent api07 'block_agent'              'block_agent (removed in 0.7)'
check_absent api07 'unblock_agent'            'unblock_agent (removed in 0.7)'
check_absent api07 'AppAgentWebsocket'        'AppAgentWebsocket (merged into AppWebsocket)'
check_absent api07 'sqlite-encrypted'         'sqlite-encrypted feature (0.7: encryption)'
check_absent api07 'wasmer_sys'               'wasmer_sys feature (0.7: wasmer-sys-cranelift)'
check_absent api07 'transport-iroh'           'transport-iroh feature (removed; iroh is unconditional)'
check_absent api07 'signal_url'               'signal_url conductor config (removed with tx5)'
check_absent api07 'webrtc_config'            'webrtc_config conductor config (removed with tx5)'
check_absent api07 'db_sync_strategy'         'db_sync_strategy (0.7: db_sync_level)'
check_absent api07 'chc_url'                  'chc_url conductor config (removed in 0.7)'
check_absent api07 'ActionBuilderCommon'      'ActionBuilderCommon (removed in 0.7)'

# ---------------------------------------------------------------------------
# 7. Tryorama: retired in favour of Sweettest
#    One pointer to the community fork is permitted; instructions are not.
# ---------------------------------------------------------------------------
section "Tryorama retirement"

TRY_HITS=$(grep -rn --include='*.md' -i 'tryorama' . \
    --exclude-dir=book --exclude-dir=MEMORY --exclude-dir=Plans \
    --exclude-dir=.local --exclude-dir=.git 2>/dev/null | grep -v '^./CHANGELOG.md:')
TRY_COUNT=$(printf '%s' "$TRY_HITS" | grep -c . || true)
if [ "$TRY_COUNT" -gt 1 ]; then
    fail tryorama "$TRY_COUNT Tryorama mentions; at most 1 community-fork pointer is allowed"
    printf '%s\n' "$TRY_HITS" | sed 's/^/        /'
else
    pass tryorama "$TRY_COUNT Tryorama mention(s)"
fi

# ---------------------------------------------------------------------------
# 8. No TODO / STUB markers outside fenced code blocks
# ---------------------------------------------------------------------------
section "TODO / STUB markers"

TODO_OUT="$TMPDIR_/todos"
: > "$TODO_OUT"
while IFS= read -r f; do
    [ -z "$f" ] && continue
    # docs/testing.md documents the check itself; exempt it.
    [ "$f" = "docs/testing.md" ] && continue
    awk -v file="$f" '
        /^[[:space:]]*```/ { infence = !infence; next }
        /TODO|STUB|PLACEHOLDER/ { if (!infence) printf "%s:%d: %s\n", file, NR, $0 }
    ' "$f" >> "$TODO_OUT"
done < "$ALL_MD"

if [ -s "$TODO_OUT" ]; then
    fail todo "$(wc -l < "$TODO_OUT" | tr -d ' ') TODO/STUB marker(s) outside code fences"
    sed 's/^/        /' "$TODO_OUT"
else
    pass todo "no TODO/STUB markers outside code fences"
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
printf '\n'
if [ "$FAILURES" -eq 0 ]; then
    printf 'PASS: all checks succeeded.\n'
    exit 0
fi
printf 'FAILED: %d check(s).\n' "$FAILURES"
exit 1

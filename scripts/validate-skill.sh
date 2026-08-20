#!/bin/sh
# validate-skill.sh — structural and currency validator for the Holochain agent skill.
#
# POSIX sh. Depends only on coreutils, grep and sed, so it runs identically in CI
# and inside `nix develop`. Exits non-zero if any check fails.
#
# Usage: scripts/validate-skill.sh [-v]
#   -v  verbose: also print each passing check
#
# Read the exit code from the SCRIPT, not from a pipeline. `validate-skill.sh |
# tail -2; echo $?` reports tail's status, so a failing run reads as 0 and a
# defect ships past a validator that caught it. Redirect and read the bare `$?`:
#   sh scripts/validate-skill.sh > /tmp/v.txt 2>&1; echo "EXIT=$?"
# In bash, `${PIPESTATUS[0]}` works too. This has bitten twice.
#
# Exemption: a line containing the marker `legacy-ok` is skipped by the
# superseded-pin, removed-API and Tryorama checks. Upgrade guides and
# troubleshooting tables have to name the old thing to tell you what to change;
# that is documentation, not an instruction. Use it sparingly and only where the
# old name is the subject rather than the recommendation.

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
    ! -path './scripts/*' \
    | sed 's|^\./||' | sort > "$ALL_MD"

# Shipped code: the templates users copy into their projects and the example
# hApp. These are NOT markdown and are deliberately absent from ALL_MD, which
# exists for routing and orphan checks. They still ship, so the forbidden-API
# and pin checks below must see them. A stale pin or a removed-in-0.7 API in
# assets/templates/ is worse than one in prose: prose is read, a template is
# copied. Build output and lockfiles are excluded; lockfiles pin transitively
# and are regenerated, not hand-maintained.
SHIPPED_CODE="$TMPDIR_/shipped_code"
find assets references/example-happ \
    \( -name '*.rs' -o -name '*.toml' -o -name '*.json' -o -name '*.nix' \
       -o -name '*.yaml' -o -name '*.yml' \) -type f \
    ! -path '*/target/*' \
    ! -name 'Cargo.lock' \
    ! -name 'flake.lock' \
    2>/dev/null | sed 's|^\./||' | sort > "$SHIPPED_CODE"

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
    # CHANGELOG.md is excluded: it is a historical record and correctly quotes
    # the pins and APIs of past releases.
    # NOTE: no `--` before the pattern. It terminates option parsing, which
    # would turn every --exclude-dir that follows into a file argument.
    hits=$(grep -rn --include='*.md' --include='*.nix' --include='*.toml' \
        --include='*.json' --include='*.yaml' --include='*.yml' \
        --exclude-dir=book --exclude-dir=MEMORY --exclude-dir=Plans \
        --exclude-dir=.local --exclude-dir=.git --exclude-dir=node_modules \
        --exclude-dir=assets --exclude=CHANGELOG.md \
        "$2" . 2>/dev/null | grep -v 'legacy-ok')
    if [ -n "$hits" ]; then
        printf 'FAIL  [%s] %s\n' "$1" "$3"
        printf '%s\n' "$hits" | sed 's/^/        /'
        FAILURES=$((FAILURES + 1))
    else
        pass "$1" "$3"
    fi
}

# Corpus of fenced code-block lines only. A removed API named in prose is
# correct documentation ("signal_url was removed in 0.7"); the same name inside
# a code fence is an instruction someone will copy. Only the latter is a defect.
CODE_LINES="$TMPDIR_/code_lines"
: > "$CODE_LINES"
while IFS= read -r f; do
    [ -z "$f" ] && continue
    awk -v file="$f" '
        /^[[:space:]]*```/ { infence = !infence; next }
        { if (infence) printf "%s:%d:%s\n", file, NR, $0 }
    ' "$f" >> "$CODE_LINES"
done < "$ALL_MD"

# Shipped code files are code end to end, so every line counts. No fence
# extraction: there are no fences, and a removed API in a template is an
# instruction whether or not it sits in a comment.
while IFS= read -r f; do
    [ -z "$f" ] && continue
    awk -v file="$f" '{ printf "%s:%d:%s\n", file, NR, $0 }' "$f" >> "$CODE_LINES"
done < "$SHIPPED_CODE"

check_absent_in_code() {
    # check_absent_in_code <label> <pattern> <explanation>
    hits=$(grep -n "$2" "$CODE_LINES" 2>/dev/null | sed 's/^[0-9]*://' | grep -v 'legacy-ok')
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

# A stale prose LABEL is not a pin and the checks above cannot see it. A table
# cell reading "HDK 0.6 API" four lines above a correct 0.7.0 pin shipped once
# already, in README.md, past a green validator. Mark a deliberate historical
# mention with a legacy-ok comment on the same line.
check_absent labels 'HD[KI] 0\.[0-6][^0-9]' 'no stale HDK/HDI 0.6-or-older prose label'

# The same pin checks over shipped code. check_absent above scans prose and
# config but excludes assets/ and lists no *.rs, so a template could carry a
# 0.6 pin past a green run. Verified: appending EntryCreationAction to
# assets/templates/integrity-lib.rs exited 0 before this block existed.
check_absent_in_code pins 'hdk = "=0\.6' 'no superseded hdk 0.6.x pin in shipped code'
check_absent_in_code pins 'hdi = "=0\.7' 'no superseded hdi 0.7.x pin in shipped code'
check_absent_in_code pins 'ref=main-0\.6' 'no superseded holonix main-0.6 ref in shipped code'
check_absent_in_code pins 'nodejs_22' 'no superseded nodejs_22 in shipped code'
check_absent_in_code pins '@holochain/client": "\^0\.20' 'no superseded @holochain/client 0.20.x in shipped code'
# Quoted forms only. The rc is named in two flake.nix comments that explain the
# trap, which is documentation; a quoted "^0.700.0-rc.1" is a pin someone installs.
# That exact defect shipped once in references/example-happ/package.json.
check_absent_in_code pins '"[\^~]\{0,1\}0\.700\.0-rc' 'no rc-era pin in shipped code'

# ---------------------------------------------------------------------------
# 6. APIs removed in Holochain 0.7 must not appear
#    This is the check that stops a pin bump from producing a skill that claims
#    0.7 while teaching 0.6.
# ---------------------------------------------------------------------------
section "Holochain 0.7 forbidden APIs"

check_absent_in_code api07 'EntryCreationAction'      'EntryCreationAction (0.7: TypedAction<EntryCreationData>)'
check_absent_in_code api07 'FlatOp::StoreEntry'       'FlatOp::StoreEntry (0.7: FlatOp::CreateEntry)'
check_absent_in_code api07 'FlatOp::StoreRecord'      'FlatOp::StoreRecord (0.7: FlatOp::CreateRecord)'
check_absent_in_code api07 'RegisterUpdate'           'FlatOp::RegisterUpdate (0.7: FlatOp::Update)'
check_absent_in_code api07 'RegisterDelete'           'FlatOp::RegisterDelete (0.7: FlatOp::Delete)'
check_absent_in_code api07 'RegisterCreateLink'       'FlatOp::RegisterCreateLink (0.7: FlatOp::Link)'
check_absent_in_code api07 'RegisterDeleteLink'       'FlatOp::RegisterDeleteLink (0.7: FlatOp::Link)'
check_absent_in_code api07 'RegisterAgentActivity'    'FlatOp::RegisterAgentActivity (0.7: FlatOp::AgentActivity)'
check_absent_in_code api07 'NewEntryAction'           'NewEntryAction (removed in 0.7)'
check_absent_in_code api07 'block_agent'              'block_agent (removed in 0.7)'
check_absent_in_code api07 'unblock_agent'            'unblock_agent (removed in 0.7)'
check_absent_in_code api07 'AppAgentWebsocket'        'AppAgentWebsocket (merged into AppWebsocket)'
check_absent_in_code api07 'sqlite-encrypted'         'sqlite-encrypted feature (0.7: encryption)'
check_absent_in_code api07 'wasmer_sys'               'wasmer_sys feature (0.7: wasmer-sys-cranelift)'
check_absent_in_code api07 'transport-iroh'           'transport-iroh feature (removed; iroh is unconditional)'
check_absent_in_code api07 'signal_url'               'signal_url conductor config (removed with tx5)'
check_absent_in_code api07 'webrtc_config'            'webrtc_config conductor config (removed with tx5)'
check_absent_in_code api07 'db_sync_strategy'         'db_sync_strategy (0.7: db_sync_level)'
check_absent_in_code api07 'chc_url'                  'chc_url conductor config (removed in 0.7)'
check_absent_in_code api07 'ActionBuilderCommon'      'ActionBuilderCommon (removed in 0.7)'

# Names that still exist in 0.7 but are called with the wrong shape. A blocklist
# cannot check arity, so it blocks the call form instead. Each of these shipped
# past the list above at least once.
check_absent_in_code api07 'GetLinksInputBuilder'     'GetLinksInputBuilder (0.7: get_links(LinkQuery::try_new(..)?, GetStrategy))'
check_absent_in_code api07 'ZomeCallResponse::Error'  'ZomeCallResponse::Error (no such variant; 0.7 has Ok/AuthenticationFailed/Unauthorized/NetworkError/CountersigningSession)'
check_absent_in_code api07 'LinkQuery::new('          'LinkQuery::new (a LinkTypes variant is TryFrom, not From: use try_new(..)?)'
check_absent_in_code api07 'SweetConductorBatch::from_config(' 'SweetConductorBatch::from_config (0.7: standard(n) / from_config_rendezvous(n, cfg))'
check_absent_in_code api07 'delete_link(link.create_link_hash)' 'delete_link with one argument (0.7: delete_link(hash, GetOptions::default()))'
check_absent_in_code api07 'consistency(&\['          'await_consistency(&[&cell, ..]) yields Item = &&SweetCell; drop the outer & or pass owned cells'

# ---------------------------------------------------------------------------
# 7. Tryorama: retired in favour of Sweettest
#    One pointer to the community fork is permitted; instructions are not.
# ---------------------------------------------------------------------------
section "Tryorama retirement"

TRY_HITS=$(grep -rn --include='*.md' -i 'tryorama' . \
    --exclude-dir=book --exclude-dir=MEMORY --exclude-dir=Plans \
    --exclude-dir=.local --exclude-dir=.git 2>/dev/null | grep -v '^./CHANGELOG.md:' | grep -v 'legacy-ok')
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

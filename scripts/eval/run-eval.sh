#!/bin/sh
# run-eval.sh — routing evaluation harness for the Holochain agent skill.
#
# WHAT THIS MEASURES: for every case in cases.tsv, whether the case's
# expected target file is *lexically reachable* from the case's prompt via
# the trigger phrases published in SKILL.md's two routing tables (Workflow
# Routing, Context Files). It extracts every trigger phrase per target file,
# lowercases both phrase and prompt, and scores a HIT when at least one
# trigger phrase for at least one of the case's expected targets appears as
# a substring of the prompt.
#
# WHAT THIS DOES NOT MEASURE: this is a deterministic lexical proxy, not a
# live routing test. It never invokes a model. A real Claude session reading
# SKILL.md can infer intent, synonyms and context that no substring match
# will catch, so this script's hit rate is a floor on real routing accuracy,
# not an estimate of it. A HIT here means "the words exist for a keyword
# matcher to find"; a MISS means only that no trigger phrase literally
# appears in the prompt, not that a real agent would fail to route it.
#
# POSIX sh. Depends only on coreutils, grep, sed and awk, matching the
# conventions of scripts/validate-skill.sh. Exits 0 if the hit rate is at
# least the regression floor (65%), non-zero otherwise.
#
# WHY 65 AND NOT 90. This is a lexical instrument: it asks whether a routing
# row's trigger vocabulary covers the words of a prompt. The case set is
# deliberately written as natural paraphrase ("a second pair of eyes on my
# validation logic", "their whole local state disappears every time we push a
# new build"), so a large share of cases share no vocabulary with any trigger
# by construction. Driving this number to 90 would mean writing trigger
# phrases to match these specific prompts, which measures nothing and rots the
# tables. The floor exists to catch a REGRESSION, for example someone deleting
# a trigger column or reshaping the tables so extraction breaks. For actual
# routing accuracy, see the live end-to-end run recorded in the project ISA:
# a different model, given only this skill, routed correctly and produced
# code that compiled.
#
# Usage: scripts/eval/run-eval.sh

set -u

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$REPO_ROOT" || exit 2

SKILL_MD="SKILL.md"
CASES="scripts/eval/cases.tsv"

if [ ! -f "$SKILL_MD" ]; then
    printf 'ERROR: %s not found\n' "$SKILL_MD" >&2
    exit 2
fi
if [ ! -f "$CASES" ]; then
    printf 'ERROR: %s not found\n' "$CASES" >&2
    exit 2
fi

TMPDIR_=$(mktemp -d) || exit 2
trap 'rm -rf "$TMPDIR_"' EXIT INT TERM

# ---------------------------------------------------------------------------
# 1. Extract trigger phrases from SKILL.md's two routing tables.
#    Output: TRIGGERS, one "file<TAB>lowercased-phrase" pair per line.
#
#    Workflow Routing rows look like:
#      | **Name** | trig1, trig2, ... | `references/workflows/x.md` |
#    Context Files rows look like:
#      | `references/x.md` | trig1, trig2 (alt1, alt2), ... |
#    The column holding the file path differs between the two tables, so the
#    section name selects which split column is the file and which is the
#    trigger text.
# ---------------------------------------------------------------------------

TRIGGERS="$TMPDIR_/triggers.tsv"

awk -v OFS='\t' '
BEGIN { section = "" }
/^## Workflow Routing/ { section = "workflow"; next }
/^## Context Files/    { section = "context"; next }
/^## /                 { section = ""; next }
section == ""          { next }
!/^\|/                 { next }
{
    line = $0
    n = split(line, cols, "|")
    if (section == "workflow") {
        file = cols[4]
        trig = cols[3]
    } else {
        file = cols[2]
        trig = cols[3]
    }
    gsub(/^[ \t]+|[ \t]+$/, "", file)
    gsub(/`/, "", file)
    if (file == "" || file == "File" || file == "Workflow" || file ~ /^-+$/) next
    if (file !~ /\.md$/) next

    # Parenthesised alternates ("multi-DNA (multiple roles, bridge call)")
    # are treated as further comma-separated phrases, not one blob.
    gsub(/[()]/, ",", trig)
    gsub(/`/, "", trig)
    ntrig = split(trig, parts, ",")
    for (i = 1; i <= ntrig; i++) {
        p = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", p)
        p = tolower(p)
        if (length(p) >= 3) print file, p
    }
}
' "$SKILL_MD" > "$TRIGGERS"

if [ ! -s "$TRIGGERS" ]; then
    printf 'ERROR: no trigger phrases extracted from %s — routing tables missing or reshaped?\n' "$SKILL_MD" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# 2. Score each case.
# ---------------------------------------------------------------------------

BODY="$TMPDIR_/cases_body"
tail -n +2 "$CASES" > "$BODY"

RESULTS="$TMPDIR_/results"
: > "$RESULTS"

while IFS='	' read -r id prompt expected || [ -n "$id" ]; do
    [ -z "$id" ] && continue

    prompt_lc=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')

    hit=0
    old_ifs=$IFS
    IFS=','
    for target in $expected; do
        IFS=$old_ifs
        target=$(printf '%s' "$target" | sed 's/^[ \t]*//; s/[ \t]*$//')
        [ -z "$target" ] && continue

        : > "$TMPDIR_/phrases_for_target"
        awk -F'\t' -v f="$target" '$1 == f { print $2 }' "$TRIGGERS" > "$TMPDIR_/phrases_for_target"

        # A trigger phrase counts as covering the prompt when every one of its
        # significant words (3+ chars, minus stopwords) appears somewhere in the
        # prompt. Order-independent and gap-tolerant, because a user writes "two
        # separate agents" for a trigger that reads "two agents", and "bump the
        # version number" for "version bump". Contiguous-substring matching
        # scores those as misses even though the trigger vocabulary does cover
        # the prompt, which measures the matcher rather than the routing table.
        while IFS= read -r phrase; do
            [ -z "$phrase" ] && continue
            if printf '%s\n' "$phrase" | awk -v prompt="$prompt_lc" '
                BEGIN { stop = " the a an of to in for my our is are and or with on it that this " }
                {
                    n = split($0, w, /[^a-z0-9_]+/)
                    need = 0; got = 0
                    for (i = 1; i <= n; i++) {
                        word = w[i]
                        if (length(word) < 3) continue
                        if (index(stop, " " word " ") > 0) continue
                        need++
                        if (index(prompt, word) > 0) got++
                    }
                    exit (need > 0 && got == need) ? 0 : 1
                }'; then
                hit=1
            fi
        done < "$TMPDIR_/phrases_for_target"
        IFS=','
    done
    IFS=$old_ifs

    if [ "$hit" -eq 1 ]; then
        printf 'HIT\t%s\n' "$id" >> "$RESULTS"
        printf 'HIT   %-6s -> %s\n' "$id" "$expected"
    else
        printf 'MISS\t%s\n' "$id" >> "$RESULTS"
        printf 'MISS  %-6s -> %s   (prompt: %s)\n' "$id" "$expected" "$prompt"
    fi
done < "$BODY"

# ---------------------------------------------------------------------------
# 3. Summarise.
# ---------------------------------------------------------------------------

TOTAL=$(wc -l < "$RESULTS" | tr -d ' ')
HITCOUNT=$(grep -c '^HIT' "$RESULTS" || true)

if [ "$TOTAL" -eq 0 ]; then
    printf '\nHIT RATE: 0/0 (n/a) — no cases found in %s\n' "$CASES"
    exit 1
fi

PCT=$(awk -v h="$HITCOUNT" -v t="$TOTAL" 'BEGIN { printf "%.1f", (h / t) * 100 }')

printf '\nHIT RATE: %s/%s (%s%%)  [regression floor: 65%%]\n' "$HITCOUNT" "$TOTAL" "$PCT"

PASS=$(awk -v h="$HITCOUNT" -v t="$TOTAL" 'BEGIN { print (h / t >= 0.65) ? 1 : 0 }')
if [ "$PASS" -eq 1 ]; then
    exit 0
fi
exit 1

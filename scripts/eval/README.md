# Routing Evaluation Harness

Checks whether a realistic user prompt would lexically reach the file `SKILL.md` intends it to reach, by matching the prompt against the trigger phrases published in `SKILL.md`'s two routing tables (Workflow Routing and Context Files).

## What this measures

For each case in `cases.tsv`, the harness:

1. Extracts every trigger phrase from `SKILL.md`'s Workflow Routing and Context Files tables, associated with the file path each row routes to.
2. Lowercases the case's prompt and every trigger phrase for the case's expected target(s).
3. Scores a **HIT** if at least one trigger phrase for at least one expected target appears as a literal substring of the prompt. Otherwise it scores a **MISS**.

This is a deterministic lexical proxy for routing accuracy, not a measurement of it. It never calls a model. It answers a narrower question: "do the words needed to find this file already exist in the trigger tables, in some form a substring match can catch?"

## What this does not measure

- Whether a real Claude Code session, reading `SKILL.md` in full, would actually route the prompt correctly. A model can use synonyms, infer intent from context it wasn't given a keyword for, and read the surrounding prose beyond just the trigger column. This harness cannot do any of that, so its hit rate is a **floor** on real routing accuracy, not an estimate of it.
- Content quality, correctness, or completeness of the target file once reached. `docs/testing.md`'s T3.x and T9.x rows already cover that ground; this harness only checks reachability.
- Multi-turn conversations, follow-up questions, or prompts that combine several unrelated asks.
- Case sensitivity nuances or stemming (plurals, verb forms). The match is a plain substring test after lowercasing, so `"distribute"` will not match `"distribution"`, and `"cap grant"` will not match `"capability grants"`. A MISS caused by this is a finding about the trigger table's wording, not proof the prompt is unroutable.

## How to run

```sh
sh scripts/eval/run-eval.sh
```

It prints one `HIT` or `MISS` line per case (a `MISS` line also echoes the prompt so the gap is visible without opening `cases.tsv`), then a summary line:

```
HIT RATE: n/m (pp%)
```

Exit code is `0` when the hit rate is at least the **regression floor of 65%**, non-zero otherwise.

The floor is deliberately not 90%. This is a lexical instrument: it asks whether a routing row's trigger vocabulary covers the words of a prompt, order-independently, after dropping stopwords. The case set is written as natural paraphrase on purpose, so cases like "a second pair of eyes on my validation logic" or "their whole local state disappears every time we push a new build" share no vocabulary with any trigger and cannot be matched lexically no matter how good the routing table is. Driving the number to 90 would mean adding trigger phrases that match these exact prompts, which measures the test rather than the skill and leaves the tables full of dead vocabulary.

So treat this as a **regression guard**, not an accuracy metric. It fires when someone deletes a trigger column, reshapes the routing tables so extraction breaks, or removes a reference file's triggers wholesale. For real routing accuracy, run a model against the skill end to end and check whether the code it writes compiles. The script depends only on `sh`, coreutils, `grep`, `sed`, and `awk`, matching `scripts/validate-skill.sh`'s conventions, so it runs the same in CI and inside `nix develop`.

## How to add a case

Append a row to `cases.tsv` (tab-separated, so use an actual tab between columns, not spaces):

```
id	prompt	expected
```

- `id`: a short unique identifier. Use the `R` prefix for a direct case or `O` for an oblique (symptom-described) case, followed by a number, so IDs never collide with the hand-written `T`-prefixed matrix in `docs/testing.md`.
- `prompt`: something a Holochain developer would actually type. Paraphrase the request naturally, don't lift the trigger phrase verbatim from `SKILL.md`, that defeats the point of the check.
- `expected`: one file path relative to the repo root that the routing tables point to, or several comma-separated paths (no spaces around the commas) if more than one target is a legitimate answer for that prompt. A case scores a HIT if any one of the listed targets is lexically reachable.

Re-run `sh scripts/eval/run-eval.sh` after adding cases. A new MISS is not itself a bug: it means the trigger tables don't yet contain wording that a substring match can find for that phrasing. Decide, case by case, whether the routing table is missing something or the prompt is genuinely edge-case; do not add trigger keywords just to inflate the score.

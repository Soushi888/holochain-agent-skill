## What does this change?

<!-- Describe what changed and why. If this fixes an issue, reference it (e.g. "Fixes #123"). -->

## Checklist

- [ ] `sh scripts/validate-skill.sh` passes locally (paste the exit code / output below if it's not obviously green)
- [ ] No API shape was written from recall; any Rust example matches a shape that actually compiles in `skills/holochain/references/example-happ/`
- [ ] If Rust code under `skills/holochain/references/example-happ/` changed, the example hApp still compiles (`cargo build` / relevant `cargo test`)
- [ ] Version pins are consistent across all files touched (bumped with `scripts/bump-versions.sh`, never hand-edited)
- [ ] No personal, private, or PAI-specific content was added (no `~/.claude/PAI/` references, no personal file paths, no private tooling)

## Validator output

<!-- Paste the output of `sh scripts/validate-skill.sh -v` here, or its exit code. -->

## Notes for reviewers

<!-- Anything a reviewer should pay special attention to, or context that doesn't fit above. -->

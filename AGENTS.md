# AGENTS.md

Two audiences. If someone handed you this repository's URL and asked you to
install the skill, read the first section and stop. If you are changing files
here, read the second.

---

## Installing this skill

Run this from the root of the project that should get the skill:

```bash
bunx holochain-agent-skills install --yes
```

It detects which agent harnesses the project uses, installs into every one it
finds, and prints where each copy landed. It never prompts when there is no
interactive terminal, so it is safe to run unattended. `npx` works identically
if `bun` is unavailable.

No `bun` and no `npx`:

```bash
mkdir -p .claude/skills && curl -fsSL https://github.com/Soushi888/holochain-agent-skills/releases/latest/download/holochain-agent-skills.tar.gz | tar -xz -C .claude/skills
```

Replace `.claude/skills` with your harness's path if it differs. The archive's
root is one directory per skill, so the extraction lands
`.claude/skills/holochain/SKILL.md` with no rename step.

Useful flags: `--global` installs into the home-directory scope instead of the
project, `--target claude,opencode` picks specific harnesses, `--link`
symlinks rather than copies so a `git pull` updates the install, and
`--dry-run` prints what would happen. `bunx holochain-agent-skills list` shows
the skills in the package and every harness path it knows.

### Confirming it worked

`SKILL.md` should exist under the printed path. Restart the agent afterwards:
most harnesses read skills once, at startup.

### What you just installed

A skill for Holochain hApp development pinned to **Holochain 0.7**: HDK 0.7.0,
HDI 0.8.0, holonix `main-0.7`. It covers coordinator and integrity zome
architecture, entry and link types, validation, capability grants, membranes,
Sweettest, the TypeScript client, and packaging. If the project you are
working in uses Holochain 0.6 or earlier, this skill will actively mislead
you: it documents the 0.7 action model and deliberately carries no 0.6 API
content. Use the `v0.2.0` tag for 0.6.

---

## Working on this repository

`CLAUDE.md` is the authoritative guide: layout, routing architecture, version
pins, and the rules for editing reference files. `CONTRIBUTING.md` covers the
contribution workflow. Read one of them before changing anything.

Three things worth knowing before your first edit:

**Only `skills/` ships.** Everything else in the repository is workshop:
`docs/`, `scripts/`, `nix/`, `book.toml`, the community files. A consumer who
installs this package gets `skills/holochain/` and nothing else. If you add a
file that consumers need, it goes under `skills/holochain/`.

**Never write an API shape from recall.** Every Rust example must match
something that compiles in `skills/holochain/references/example-happ/`, which
is a real hApp with a passing Sweettest suite. If you cannot point at the line
that proves a shape, do not write it.

**The validator is the gate, and it is not advisory:**

```bash
sh scripts/validate-skill.sh      # structure, routing, links, pins, removed APIs
sh scripts/eval/run-eval.sh       # routing regression floor
sh scripts/check-versions.sh      # the four version declarations agree
```

Read the exit code from the script itself, not from a pipeline. `validate-skill.sh
| tail -2; echo $?` reports `tail`'s status, so a failing run reads as success.
This has bitten twice.

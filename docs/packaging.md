# Packaging Architecture

How this repository turns one directory of markdown into something four different
kinds of consumer can install, and why each decision went the way it did. Written
alongside the v1.0 packaging work; read it before changing anything under
`scripts/`, `nix/`, `package.json` or the `files` array.

## The problem it solves

Before v1.0 the repository root *was* the skill. Anything that fetched the
repository got the whole workshop. Nondominium's `flake.nix` did

```
rsync -a --delete ${inputs.holochain-agent-skill}/ .claude/skills/holochain/
```

which put `book.toml`, `SUMMARY.md`, `CHANGELOG.md`, `CLAUDE.md`, `docs/` and
`.github/` inside the installed skill. Every one of those files is context an
agent may read and none of it is skill content.

It was also a spec violation. agentskills.io requires the frontmatter `name` to
equal the parent directory name. The frontmatter said `holochain` and the
directory said `holochain-agent-skill`. It worked only because every installer
renames on copy, which means the repository was relying on a behaviour the spec
does not promise.

## Requirements

**Functional.** One payload, reachable four ways: an npm package, a downloadable
archive, a Nix derivation, and a git clone. An agent handed only the repository
URL must be able to install unaided. Adding a second skill must be a new
directory, not a restructure.

**Non-functional.** No artefact may contain a file outside the payload, and that
must be *asserted* rather than trusted. No gate may pass vacuously. Archives must
be reproducible, so a checksum published in a Nix expression stays valid. Nothing
in the pipeline may block on human input, because the primary caller is an agent.

**Constraint.** The repository is documentation plus one compiling reference
hApp. It has no application runtime, so the packaging layer must not introduce
one: zero runtime dependencies, and every gate runnable from a POSIX shell.

## Shape

```
┌────────────────────────────────────────────────────────────────────────┐
│ SOURCE OF TRUTH   skills/<name>/                                       │
├────────────────────────────────────────────────────────────────────────┤
│ SKILL.md   references/   assets/   LICENSE                             │
│                                                                        │
│ The only tree that ships. Everything else in the repo is               │
│ workshop and must never reach a consumer.                              │
└────────────────────────────────────────────────────────────────────────┘
                                    │                                     
                                    ▼                                     
┌────────────────────────────────────────────────────────────────────────┐
│ GATES   run before any artefact is built                               │
├────────────────────────────────────────────────────────────────────────┤
│ validate-skill.sh      structure, routing, links, pins, dead APIs      │
│ run-eval.sh            routing regression floor (65%)                  │
│ check-versions.sh      the four version declarations agree             │
└────────────────────────────────────────────────────────────────────────┘
                                    │                                     
                                    ▼                                     
┌────────────────────────────────────────────────────────────────────────┐
│ BUILDERS   one payload, three artefact shapes                          │
├────────────────────────────────────────────────────────────────────────┤
│ npm pack               files: [skills, bin, README.md, LICENSE]        │
│ build-release-assets   tar.gz + zip, root = one dir per skill          │
│ nix/skill.nix          derivation, root = the skill itself             │
└────────────────────────────────────────────────────────────────────────┘
                                    │                                     
                                    ▼                                     
┌────────────────────────────────────────────────────────────────────────┐
│ CHANNELS   what a consumer reaches for                                 │
├────────────────────────────────────────────────────────────────────────┤
│ bunx holochain-agent-skills install --yes      (agents, humans)        │
│ curl ... | tar -xz -C .claude/skills           (no node)               │
│ lib.mkSkillsHook / packages.<system>.holochain (Nix)                   │
│ node bin/install.mjs install --link            (skill authors)         │
└────────────────────────────────────────────────────────────────────────┘
                                    │                                     
                                    ▼                                     
┌────────────────────────────────────────────────────────────────────────┐
│ HARNESS PATHS   resolved by detection, never assumed                   │
├────────────────────────────────────────────────────────────────────────┤
│ .claude/skills   .agents/skills   .opencode/skills                     │
│ .github/skills   .gemini/skills   .cursor/skills                       │
└────────────────────────────────────────────────────────────────────────┘
```

Everything flows one way. The payload is never assembled from anything but
`skills/`, the gates always run before a builder, and no builder reaches into the
workshop.

## Components

### `skills/<name>/` — the payload

Plural `skills/`, singular skill directories. The plural buys the v2 ecosystem
skills (`skills/hrea/`, `skills/holochain-open-dev/`) without another
restructure, and it matches the layout the npm skill-manager ecosystem already
indexes. The singular directory name is not a style choice: the spec ties it to
the frontmatter `name`, and installers derive the install path from it.

### `scripts/validate-skill.sh` — the structural gate

Every path derives from a single `SKILL_DIR`, so adding a second skill is a loop
rather than a rewrite. Routing targets inside `SKILL.md` stay relative to the
skill root, so the skill is position-independent: the same `SKILL.md` works at
`skills/holochain/` in the repo and at `.claude/skills/holochain/` once
installed. Only the validator knows about the prefix.

It gained a name-matches-directory check with the move, which is the check that
would have caught the original violation.

### `scripts/install.ts` — the installer

Compiled to `bin/install.mjs` with `bun build --target=node`, so the source is
TypeScript and the published binary runs under plain node with no dependencies.
Both entry points resolve the payload identically, one level up from the file.

Its decision tree exists because **the primary caller is an agent, not a person**:

| Detected | TTY | Behaviour |
|----------|-----|-----------|
| none | either | `.claude/skills` and `.agents/skills`, and says so |
| exactly one | either | that one, silently |
| more than one | yes | numbered prompt, Enter for all |
| more than one | no | all of them, prints the list |

A blocking prompt in the no-TTY row would be a hang, not a question. That row is
the whole reason the tree exists.

The harness table carries a source citation per path. This is the one table in
the package where being wrong is **silent**: installing into a directory nothing
scans looks exactly like a successful install. Nothing goes in it from recall.

### `scripts/build-release-assets.sh` — the archives

Archive root is one directory per skill, not a versioned directory, so
`tar -xzf ... -C .claude/skills` is genuinely one command. A versioned root would
force a `--strip-components` dance, and the entire point of the curl fallback is
that it is one line somebody can paste.

Content comes from `git archive`, so an untracked `target/` in a working tree
cannot leak into a release.

### `flake.nix`, `nix/skill.nix`, `nix/mk-skills-hook.nix` — the Nix surface

Two output shapes, deliberately:

- `packages.<system>.<name>` is rooted **at the skill**, so `${it}/SKILL.md`
  exists and it can be rsynced or symlinked straight into a harness directory.
- `packages.<system>.default` is the **bundle**, one directory per skill, the
  same shape as the release archive.

`nix/skill.nix` runs the validator in its check phase. A broken routing path
fails `nix build` rather than reaching a project.

`mkSkillsHook` exists because every consumer writes the same rsync glue and gets
the same thing wrong. Measured: without `--chmod=u+w` the materialised tree comes
out `dr-xr-xr-x` / `-r--r--r--`, and a later `mkdir` inside it fails with
"Permission denied" while a repeat rsync still succeeds. The symptom therefore
never appears where it was caused, which is why it reads as an unrelated
shellHook failure.

## Decisions and trade-offs

| # | Decision | Rejected alternative | Why |
|---|----------|---------------------|-----|
| D1 | Payload under `skills/<name>/` | `skill/` singular | Plural leaves room for the v2 ecosystem skills and matches what npm skill managers index |
| D2 | Repo `holochain-agent-skills`, skill `holochain` | Match them | The spec ties the directory to the frontmatter name; the repo is free to describe the collection |
| D3 | Explicit `install` command | npm `postinstall` | `bun add` must never write into a consumer's tree. An install that mutates a project by surprise is worse than one extra command |
| D4 | Unscoped npm name at 1.0 | Wait for `@holochain` | The scope belongs to the Holochain Foundation. Ask after shipping; never let a release wait on a third party's decision |
| D5 | Detection by marker directory | Detect the skills directory | The skills directory usually does not exist yet, which is exactly the case an installer is for, so testing for it detects nothing |
| D6 | Two Nix output shapes | One | Consumers want the skill root; the bundle mirrors the archive. Collapsing them makes one of the two callers wrong |
| D7 | Assert tarball contents in CI | Trust the `files` array | The array is the only thing between a consumer and a skill directory full of CI config, and it is one typo wide |
| D8 | Reproducible archives | Ship whatever tar emits | A checksum pinned in a Nix expression must stay valid across rebuilds of the same commit |

## Failure modes, and what catches each

| Failure | Caught by | Fails at |
|---------|-----------|----------|
| Workshop file reaches a consumer | `package` CI job asserting the pack manifest | pull request |
| Frontmatter name drifts from the directory | validator, and again in the Nix check phase | pull request and `nix build` |
| A routing target is deleted or renamed | validator resolution check | pull request |
| A removed-in-0.7 API enters a template | validator forbidden-API scan over shipped code | pull request |
| Version declarations drift apart | `check-versions.sh`, three in-tree and again against the tag | pull request and release |
| The installer stops installing | smoke test running it for real into a scratch project | pull request and release |
| An archive changes shape | extract-and-assert step | pull request and release |
| A published checksum stops matching | two builds compared | manual, on change to the builder |

The pattern is that every gate has a negative probe. A gate that has never been
observed failing is a gate nobody has tested.

## Consumer migration: Nondominium

Nondominium is the only known consumer of the pre-1.0 layout. Its `flake.nix`
takes the repository as a non-flake source input and rsyncs the tree root into
three harness directories through a local `nix/agent-skills.nix`.

**The path is not the interesting part of this migration.** Nondominium pins
`holonix ref=main-0.6`, and the v1.0 skill is Holochain 0.7 only, by decision, <!-- legacy-ok: naming the old pin is the subject here, not a recommendation -->
with all 0.6 API content deleted. Pointing a 0.6 codebase at the 1.0 skill would
hand its agents an authoritative-looking reference for an action model that
project does not use. That is worse than a stale skill, because it reads as
current.

So the migration is two moves, not one, and they are ordered:

**Move 1, now: pin the last 0.6-era release and say why.** v0.2.0 predates the
restructure, so its tree root is still the skill and no path change is needed.
This is a one-line edit that stops `nix flake update` from silently pulling 1.0
onto a 0.6 project.

```nix
# Holochain 0.6 content. v1.0.0+ is 0.7-only and would misdescribe this
# codebase; bump it in the same PR that moves holonix to main-0.7.
holochain-agent-skill = {
  url   = "github:Soushi888/holochain-agent-skills/v0.2.0";
  flake = false;
};
```

**Move 2, inside Nondominium's own 0.7 upgrade PR:** take the 1.0 skill, adopt
the subdirectory, and delete the local glue. `mkSkillsHook` replaces
`nix/agent-skills.nix` entirely.

```nix
inputs.holochain-agent-skills.url =
  "github:Soushi888/holochain-agent-skills/v1.0.0";   # a flake from 1.0 on

# in shellHook, replacing the agentSkillsHook call:
${inputs.holochain-agent-skills.lib.mkSkillsHook {
  inherit pkgs;
  skills = [
    { src = inputs.holochain-agent-skills.packages.${system}.holochain;
      name = "holochain"; }
    { src = "${./pai/claude}/skills/nondominium-domain";
      name = "nondominium-domain"; }
    { src = "${./pai/claude}/skills/complexity-oriented-programming";
      name = "complexity-oriented-programming"; }
  ];
}}
```

Two notes for whoever does move 2. `mkSkillsHook` passes `--chmod=u+w` itself, so
the skills no longer need Nondominium's `chmod -R u+w` workaround; the
`pai/claude` materialisation above it still does, since that rsync is unrelated.
And `mkSkillsHook` defaults to `.claude`, `.cursor` and `.agents`, which is
exactly the three paths the local helper hardcoded, so the behaviour is
unchanged.

**Acceptance for both moves:** `nix develop` produces
`.claude/skills/holochain/SKILL.md` and no `book.toml` anywhere beneath it.

## What this design does not do

No registry, no update checker, no telemetry, no version negotiation between a
skill and a harness. A skill is a directory of markdown; the moment the packaging
layer becomes more complicated than the thing it packages, it has failed.

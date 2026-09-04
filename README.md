# Holochain Agent Skills

[![Validate](https://github.com/Soushi888/holochain-agent-skills/actions/workflows/validate.yml/badge.svg)](https://github.com/Soushi888/holochain-agent-skills/actions/workflows/validate.yml)
[![npm](https://img.shields.io/npm/v/holochain-agent-skills)](https://www.npmjs.com/package/holochain-agent-skills)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/Soushi888/holochain-agent-skills)

Agent skills for Holochain hApp development, built to the
[Agent Skills Open Standard](https://agentskills.io) so they work in Claude Code, opencode,
GitHub Copilot, Cursor, Gemini CLI and every other tool that adopted the format. Pinned to
**Holochain 0.7**, verified against a reference hApp that actually compiles.

## Install

```bash
bunx holochain-agent-skills install --yes
```

Run it from the root of the project that should get the skill. It detects which agent
harnesses the project uses, installs into all of them, and prints where each copy landed.
`npx` works the same if you do not have `bun`.

Without either, one command and no pipe into a shell:

```bash
mkdir -p .claude/skills && curl -fsSL https://github.com/Soushi888/holochain-agent-skills/releases/latest/download/holochain-agent-skills.tar.gz | tar -xz -C .claude/skills
```

Restart your agent afterwards. Most harnesses read skills once, at startup. Then ask it
anything about Holochain, or invoke it by name (`/holochain` in Claude Code).

<details>
<summary>Other ways to install</summary>

**Pin it in the project.** Installing does not write into your tree, so the version is
recorded where you can see it:

```bash
bun add -d holochain-agent-skills
bunx holochain-skills install --yes
```

**Globally, for every project on the machine:**

```bash
bunx holochain-agent-skills install --global --yes
```

**Pick specific harnesses**, instead of every one detected:

```bash
bunx holochain-agent-skills install --target claude,opencode
bunx holochain-agent-skills list          # every skill and every known harness path
```

**Symlink instead of copy**, so `git pull` updates the installed skill:

```bash
git clone https://github.com/Soushi888/holochain-agent-skills ~/holochain-agent-skills
cd your-project && node ~/holochain-agent-skills/bin/install.mjs install --link
```

**Nix.** Either take the source tree and point at the subdirectory:

```nix
inputs.holochain-agent-skills = {
  url = "github:Soushi888/holochain-agent-skills/v1.0.0";
  flake = false;
};
# consume: "${inputs.holochain-agent-skills}/skills/holochain"
```

or use the flake, which also hands you the devShell glue:

```nix
inputs.holochain-agent-skills.url = "github:Soushi888/holochain-agent-skills/v1.0.0";

# in your devShell:
shellHook = ''
  ${inputs.holochain-agent-skills.lib.mkSkillsHook {
    inherit pkgs;
    skills = [{
      src  = inputs.holochain-agent-skills.packages.${system}.holochain;
      name = "holochain";
    }];
  }}
'';
```

`packages.<system>.holochain` is rooted at the skill itself, so `${it}/SKILL.md` exists.
`packages.<system>.default` is the bundle, one directory per skill, matching the release
archive. `mkSkillsHook` writes into `.claude/skills`, `.cursor/skills` and `.agents/skills`
by default; pass `targets` to change that. It exists because every consumer writes the same
rsync glue and hits the same wall: Nix store paths are read-only and `rsync -a` preserves
that mode, so the *second* `nix develop` fails with a permission error. The hook passes
`--chmod=u+w`.

</details>

### Where it installs

Detection looks for each harness's marker directory in the project root, or in `$HOME` with
`--global`. Exactly one found means that one is used; several found means all of them, or an
interactive choice if you are at a terminal; none found falls back to `.claude/skills` and
`.agents/skills`.

| Harness | Project path | Global path |
|---------|--------------|-------------|
| Claude Code | `.claude/skills` | `~/.claude/skills` |
| Agent Skills (tool-agnostic) | `.agents/skills` | `~/.agents/skills` |
| opencode | `.opencode/skills` | `~/.config/opencode/skills` |
| GitHub Copilot | `.github/skills` | `~/.copilot/skills` |
| Gemini CLI | `.gemini/skills` | `~/.gemini/skills` |
| Cursor | `.cursor/skills` | `~/.cursor/skills` |

The installer never prompts without an interactive terminal, so an agent or a CI job can run
it unattended.

## What it covers

| Domain | Description |
|--------|-------------|
| **Architecture** | Coordinator and integrity zome split, DNA structure, Cargo workspace, Nix dev environment, progenitor pattern, multi-DNA, private entries |
| **Design** | DHT data modeling, entry and link type design, discovery strategy, validation rules |
| **Scaffold** | Holonix setup, Nix flake, `hc` CLI, `hc scaffold`, new project and new domain workflows |
| **Implement** | Entry types, link types, CRUD, cross-zome calls, signals, validation, HDK 0.7 API |
| **Test** | Sweettest two-agent scenarios, `await_consistency`, update and delete patterns, inline zomes |
| **Deploy** | Kangaroo-Electron packaging, `.webhapp` bundling, CI/CD, versioning, auto-update |

**Version pins:** `hdk = "=0.7.0"` | `hdi = "=0.8.0"` | `holonix ref=main-0.7`

This release targets Holochain 0.7 only, and carries no 0.6 API content by design. On a 0.6
project it will actively mislead you. Use the `v0.2.0` tag for 0.6, or the skill's
`UpgradeHolochain07` workflow to port.

## Quick start

```
# Design a new data model
/holochain design data model for a marketplace listing with status transitions

# Scaffold a new hApp from scratch
/holochain scaffold new happ called my-network

# Implement a full CRUD zome
/holochain implement zome for Profile entry type

# Debug a flaky test
/holochain my Sweettest passes alone but fails when Bob reads Alice's entry

# Package for distribution
/holochain deploy package my happ for desktop distribution
```

## Workflow triggers

| Say... | Triggers |
|--------|---------|
| "design data model", "model entries", "what entries" | DesignDataModel |
| "scaffold", "new happ", "new project", "setup environment" | Scaffold |
| "implement zome", "create zome", "write zome" | ImplementZome |
| "design access control", "cap grant", "who can call" | DesignAccessControl |
| "upgrade to 0.7", "port from 0.6", "migrate hApp" | UpgradeHolochain07 |
| "deploy", "package", "webhapp", "kangaroo" | PackageAndDeploy |

## Ecosystem roadmap

**v1 (current):** the full development cycle. Architecture, design, scaffold, implement,
test, deploy.

**v2 (planned):** ecosystem expansion, as further skills in this repository.

- hREA and ValueFlows
- holochain-open-dev patterns
- ADAM (coasys) integration
- unyt integration

**v3 (vision):** GUI and visual tooling. A visual DHT data model explorer, architecture
diagram generation, progressive disclosure from junior to senior.

## Repository layout

`skills/` is the shipped payload. Everything else exists to build, validate, document and
release it, and never reaches an installed copy.

```
skills/holochain/              THE SKILL. Nothing outside this directory ships.
  SKILL.md                       Entry point: routing table, context index, quick reference,
                                 toolchain currency and companion-library tables
  references/                    Reference material, loaded on demand
    architecture.md                Coordinator/integrity split, DNA structure, workspace, Nix
    progenitor.md                  Progenitor pattern, DNA properties, bootstrap founder
    patterns.md                    Entry types, links, CRUD, validation, signals, HDK 0.7 API
    scaffolding.md                 Holonix, Nix flake, hc CLI, hc scaffold
    access-control.md              Capability grants, cap claims, remote signals
    membranes.md                   genesis_self_check, membrane proofs, gating who may join
    cryptography.md                App-level signing and encryption
    scheduling.md                  Scheduled functions, persisted vs ephemeral
    countersigning.md              Atomic multi-agent commits
    cell-cloning.md                Partitioned data via clone cells
    error-handling.md              thiserror and WasmError patterns
    source-chain.md                query(), introspection, host functions, validation receipts
    networking.md                  Kitsune2 and iroh, NetworkConfig, bootstrap and relay servers
    testing.md                     Sweettest patterns, two-agent scenarios, E2E
    wind-tunnel.md                 Performance and load testing
    client.md                      @holochain/client, auth tokens, admin API, signals
    deployment.md                  Kangaroo-Electron packaging and distribution
    migration.md                   DNA migration and init properties
    troubleshooting.md             Literal error strings mapped to causes
    debugging.md                   Logs, hc sandbox, hc-client, inspecting a live conductor
    frameworks/                    Svelte and Effect-TS integration
    workflows/                     Step-by-step guided sequences, routed from SKILL.md
    example-happ/                  A real, compiling 0.7 hApp: ground truth for every example
  assets/templates/              Template files (flake.nix, manifests, zome sources, harness)

scripts/                       validate-skill.sh, bump-versions.sh, check-versions.sh,
                               build-release-assets.sh, install.ts, eval/
nix/                           skill.nix, mk-skills-hook.nix
docs/                          Requirements, roadmap, testing matrix. Not part of the skill
AGENTS.md                      Install instructions addressed to an agent
```

## Contributing

Contributions welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; the short version is
that no API shape may be written from recall, and every Rust example must match something
that compiles in `skills/holochain/references/example-happ/`.

Before opening a pull request:

```bash
sh scripts/validate-skill.sh      # structure, routing, links, pins, removed APIs
sh scripts/eval/run-eval.sh       # routing regression floor
sh scripts/check-versions.sh      # the four version declarations agree
```

When updating for a new Holochain release, run `scripts/bump-versions.sh` rather than
hand-editing pins, then run the validator to confirm nothing was missed. CI runs all three
gates plus a Nix build and an mdBook build on every push and pull request.

## Documentation site

<https://soushi888.github.io/holochain-agent-skills/>

## License

Apache-2.0

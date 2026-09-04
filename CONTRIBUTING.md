# Contributing

Thanks for considering a contribution to the Holochain Agent Skill. This is a documentation-only repository: a vanilla [Agent Skills Open Standard](https://agentskills.io) skill for Holochain hApp development. There is no Rust build and no TypeScript build for the skill itself. Every file is Markdown, YAML frontmatter, or a template file, except for the reference hApp under `references/example-happ/`, which is real Rust and TypeScript that compiles.

## What this repository is

The skill is loaded by Claude Code (and other Agent Skills-compatible tools) when a user invokes `/holochain` or when Holochain-related work is detected. `SKILL.md` is the entry point: it routes to `references/workflows/*.md` for step-by-step sequences and to the other `references/*.md` files for reference material, loaded on demand rather than all at once.

The repository also generates a static documentation site with mdBook, built from `book.toml` and `SUMMARY.md`. GitHub Actions deploys it to GitHub Pages on every push to `main`.

For the full file layout and the key architectural concepts the skill teaches (coordinator/integrity split, validation determinism, update chains, and so on), read `CLAUDE.md` at the repository root before editing reference content. It is the canonical map of this repository and takes precedence over anything below if the two ever disagree.

## The hard rule: examples must compile

Every Rust code example in this skill must match an API shape that actually compiles against `references/example-happ/`, the reference hApp. `references/example-happ/` is the ground truth for the skill: it is not sample text, it is a real Holochain 0.7 project.

**Never write an API shape from recall.** Holochain's HDK and HDI change in breaking ways between minor versions, and a plausible-looking function signature that used to be correct in an older release is exactly the kind of error this skill exists to prevent. Before adding or changing a code example:

1. Find the equivalent pattern in `references/example-happ/` (or write it there first if it does not yet exist) and confirm it builds.
2. Copy the actual shape into the reference file, not a remembered approximation of it.
3. If you cannot verify a pattern against the example hApp, say so in the pull request rather than guessing.

## The validator is the gate

`scripts/validate-skill.sh` is what CI runs on every push and pull request (see `.github/workflows/validate.yml`), and it must pass locally before you open a pull request. It checks:

- `SKILL.md` frontmatter (`name`, `description`, `license`, `metadata`)
- that every routing target named in `SKILL.md` resolves to a real file
- that every skill markdown file is reachable from `SKILL.md` or `SUMMARY.md` (no orphans)
- that relative markdown links resolve
- version pin consistency between `SKILL.md` frontmatter and the rest of the skill
- that APIs removed in Holochain 0.7 are not taught as current
- that the old async test harness is not presented as the recommended one anymore (Sweettest is; at most one pointer to its community fork is allowed) <!-- legacy-ok -->
- that no leftover placeholder marker is left outside a fenced code block <!-- legacy-ok -->

Run it from the repository root:

```bash
sh scripts/validate-skill.sh
```

Add `-v` for verbose output that also prints passing checks:

```bash
sh scripts/validate-skill.sh -v
```

If the validator flags a new file you added as an orphan, that means it is not reachable from `SKILL.md`'s routing table or from `SUMMARY.md`. Add a link from the appropriate place rather than editing the validator's orphan rule to special-case your file.

## Bumping version pins

Holochain is sensitive to minor version changes, so this skill pins exact versions (`hdk = "=0.7.0"`, not `hdk = "0.7"`). **Never hand-edit a version pin.** Use `scripts/bump-versions.sh`, which rewrites every occurrence across the skill consistently:

```bash
scripts/bump-versions.sh --hdk 0.7.1 --hdi 0.8.1 --holonix main-0.7 \
  --node 24 --client 0.21.1 --hc-spin 0.700.1
```

Add `--dry-run` to preview the changes first. Bumping the pins is not the same as making the content correct: after running the script, you must run `scripts/validate-skill.sh`, which fails if any surviving code example still teaches an API that the new version removed. A green pin bump with a red validator means the skill claims a version it does not actually teach, and that pull request will not be merged as-is.

## Reporting a stale version pin

If you notice a version pin in this skill that no longer matches what a Holochain project actually needs (a newer `hdk`/`hdi` release, a new `holonix` ref, a new `@holochain/client` or `hc-spin` version), that is the single most useful and lowest-friction contribution you can make. Open an issue using the **Stale Version Pin** issue template, which asks for the component, the version the skill currently claims, the version that is actually current, and the registry URL (crates.io, npm, or the relevant git ref) proving it. You do not need to fix the pin yourself; a well-sourced report is enough for a maintainer to run `scripts/bump-versions.sh` and re-verify the surrounding prose.

## `references/workflows/` vs. the other `references/*.md` files

Files under `references/workflows/` are step-by-step guided sequences: they walk through a task from start to finish (scaffolding a project, designing a data model, implementing a zome, and so on) and are what `SKILL.md`'s Workflow Routing table points to for a given natural-language trigger.

The other files directly under `references/` (`architecture.md`, `patterns.md`, `testing.md`, `scaffolding.md`, `access-control.md`, `cell-cloning.md`, `error-handling.md`, `wind-tunnel.md`, `client.md`, `deployment.md`, `migration.md`, `troubleshooting.md`, and the `frameworks/` subdirectory) are reference material: they explain a domain rather than walking through a task. `SKILL.md`'s Context Files table routes to these on demand.

Keep this distinction when adding new content. A new step-by-step sequence belongs in `references/workflows/`; a new domain explanation belongs alongside the existing reference files. Each pattern should live in exactly one canonical file, with `SKILL.md` routing to it, rather than being duplicated across files.

## `docs/` is not part of the skill

`docs/requirements.md`, `docs/roadmap.md`, and `docs/testing.md` are project tracking: a requirements specification, a roadmap, and a testing strategy. They are not loaded by the skill's routing table at runtime, and Claude Code never reads them when the skill is invoked. Feel free to consult them for project context, but do not treat them as skill content, and do not expect changes there to affect what the skill actually teaches.

## Building the documentation site

The documentation site is built with [mdBook](https://rust-lang.github.io/mdBook/) plus the `mdbook-frontmatter-strip` preprocessor (so that each file's YAML frontmatter does not leak into the rendered page):

```bash
cargo install mdbook mdbook-frontmatter-strip
mdbook build
```

This produces the `book/` directory, which is gitignored and rebuilt from source on every push to `main` via `.github/workflows/deploy-docs.yml`. You do not need to commit anything under `book/`.

## PAI-independence: no personal or private tooling

This skill must work with **zero** PAI (Personal AI Infrastructure) dependency: no `~/.claude/PAI/` directory, no Algorithm routing, no voice notification curls, no `PROJECTS.md` references, no personal file paths, no references to any private tooling that a community contributor would not have installed. Every piece of content must be self-contained and work in a vanilla Claude Code install, or in any other Agent Skills-compatible tool.

When contributing, check that you have not introduced:

- absolute filesystem paths specific to a maintainer's machine
- shell commands that call out to personal infrastructure (voice notifications, private APIs, personal cron jobs)
- references to files or systems that only exist in a maintainer's private setup

If in doubt, ask yourself whether the instruction would still make sense to someone who cloned this repository fresh, with nothing installed beyond Nix and the Holochain toolchain.

## Opening a pull request

1. Make your changes, keeping the "examples must compile" rule and the file-role distinctions above in mind.
2. Run `sh scripts/validate-skill.sh` locally and confirm it exits `0`.
3. If you touched a code example, confirm it still matches `references/example-happ/` (or update the example hApp alongside it).
4. If you touched a version pin, use `scripts/bump-versions.sh`, not a hand edit.
5. Open the pull request. The template will ask you to confirm the above; fill it in honestly rather than skipping items.

## License

By contributing, you agree that your contributions will be licensed under the [Apache-2.0](LICENSE) license that covers this repository.

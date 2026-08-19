# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-08-17

First stable release. Targets **Holochain 0.7 only**, a clean break from 0.6.

### Added

- `references/countersigning.md`: atomic multi-agent commits, `PreflightRequest`, session times, enzymatic and M of N sessions, and the `unstable-countersigning` gate that means a stock conductor cannot run it
- `references/scheduling.md`: `schedule()`, persisted crontab versus ephemeral duration, `#[hdk_extern(infallible)]`, and why scheduled functions run as the chain author
- `references/cryptography.md`: `sign` / `sign_ephemeral`, `verify_signature` from validation, secretbox versus box, `create_x25519_keypair`, and what encryption does not buy you on a DHT
- `references/migration.md`, `references/troubleshooting.md`, and the `UpgradeHolochain07` workflow
- Warrants and chain status in `references/patterns.md`: what replaced the removed `block_agent` / `unblock_agent`, and why `ChainStatus::Valid` alone is not a clean bill of health
- A dated toolchain currency table, a companion-library table, and an unstable-feature-gate table in `SKILL.md`
- `references/example-happ/`: a real hApp that compiles and whose Sweettest suite passes, serving as the ground truth for every Rust example
- `assets/templates/`: real template files rather than inlined code blocks
- `scripts/validate-skill.sh` plus a CI workflow, and `scripts/bump-versions.sh`
- `scripts/eval/`: a lexical routing regression guard
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue forms including a stale-version report, and a PR template
- `docs/release-gate-1.0.md`: the completed release pass with evidence
- `references/networking.md`: the 0.7 network stack. Kitsune2 0.5.0 over iroh, every `NetworkConfig` field with its real default, `bootstrap_url` and `relay_url`, the three timeouts that `request_timeout_s` derives, `target_arc_factor` for leecher nodes, and self-hosting `kitsune2-bootstrap-srv`
- `references/membranes.md`: join-time gating. `genesis_self_check`, `GenesisSelfCheckDataV2`, membrane proofs in `AgentValidationPkg` validation, the deferred `provideMemproofs` flow and the `awaiting_memproofs` app status
- `references/source-chain.md`: `query()` and `ChainQueryFilter` including the hash-bounded efficiency cliff, cell introspection across `dna_info` / `zome_info` / `agent_info` / `call_info`, `sys_time` and `random_bytes`, and validation receipts
- `references/debugging.md`: reading a live conductor. `RUST_LOG` versus `WASM_LOG`, the `hc sandbox` subcommand set, and the `hc-client` admin and zome-call surface
- App authentication tokens and the admin install surface in `references/client.md`: `issueAppAuthenticationToken`, `attachAppInterface`, `installApp` with `roles_settings`, and `authorizeSigningCredentials`

### Changed

- **Breaking: repository restructured** to `SKILL.md` + `references/` + `references/workflows/` + `assets/templates/` + `scripts/`. Symlink installs pointing at the old flat layout will break
- Version pins bumped to `hdk = "=0.7.0"`, `hdi = "=0.8.0"`, holonix `ref=main-0.7`, `@holochain/client` 0.21.0, `@holochain/hc-spin` 0.700.0, `nodejs_24`
- Every Rust validation example ported to the 0.7 action model and then to the **stable v0.700.0 scaffolder idiom**: `TypedAction::<D>::try_from_action(...)?` for fallible narrowing, infallible `.into()` for Create and Update widening, and no hand-rolled `WrongActionError` plus `map_err` boilerplate
- Testing guidance moved from the retired JS harness to Sweettest throughout
- `references/wind-tunnel.md` now warns that the latest Wind Tunnel tag pins Holochain 0.6 while its `main` branch pins 0.7

### Fixed

- Documented that holonix `main-0.7` bundles `hc-scaffold 0.700.0-rc.0`, whose generated `validate()` does not compile against the stable `hdi 0.8.0` it also pins, with each symptom and its fix
- Corrected `manifest_version` from `"1"` to `"0"` in YAML examples
- Corrected the cloning prerequisite in `references/cell-cloning.md` and `references/architecture.md`. `deferred: true` is not required for a clonable role, and the conductor ignores `deferred` outright: `AppBundle::resolve_cell` destructures `Create { .. }` without reading it. `strategy: clone_only` is the setting that leaves a role unprovisioned, and assembling `AppInfo` then reaches `unimplemented!()` in `holochain_conductor_api-0.7.0` (`src/app_interface.rs` line 548). Reported by @AlchemicalSpiralizer in #2
- Removed stale `HDK 0.6` labels from `SKILL.md` and corrected `await_consistency_60s`, which does not exist, to `await_consistency`
- Documented why a bare `cargo install holochain_scaffolding_cli` installs the wrong tool: crates.io orders `0.4000.4` above `0.700.0` by semver, so the version must be pinned explicitly
- Corrected `authorizeSigningCredentials` in `references/client.md` to the 0.21 tagged union `{ type: "listed", value: [[zome, fn]] }`, replacing the 0.20-era `GrantedFunctionsType` object form, and `listCapabilityGrants` to pass the required `include_revoked`

## [0.2.0] — 2026-05-15

### Added

- mdBook documentation site — `book.toml`, `SUMMARY.md`, and GitHub Actions deploy to GitHub Pages on every push to `main`
- mdBook frontmatter-strip preprocessor — strips YAML frontmatter so it does not appear in rendered pages
- `Progenitor.md` — dedicated context file for the progenitor pattern (DnaProperties, check_if_progenitor, Moss enforcement, bootstrap auto-registration)

### Changed

- Version pins bumped: `hdk = "=0.6.1"`, `hdi = "=0.7.1"`, `holonix ref=main-0.6`

## [0.1.0] — 2026-04-01

Initial release of the Holochain agent skill.

### Added

- `SKILL.md` — entry point with workflow routing table and context-file index
- `Architecture.md` — coordinator/integrity split, DNA structure, Cargo workspace, Nix, private entries, multi-DNA
- `Patterns.md` — entry types, link types, CRUD patterns, update chain, validation, signals, HDK API
- `Scaffold.md` — Holonix setup, Nix flake, hc CLI commands, project scaffolding
- `AccessControl.md` — capability grants, cap claims, admin-only patterns, init() setup
- `CellCloning.md` — clone cells, partitioned data, createCloneCell, clone_limit
- `ErrorHandling.md` — thiserror enums, WasmError, ExternResult patterns
- `Testing.md` — Tryorama + Vitest setup, two-agent scenarios, dhtSync; Sweettest (Rust-native) patterns; three-layer testing strategy; E2E Playwright integration
- `TypeScript.md` — holochain-client setup, callZome, signals, SvelteKit integration
- `Deployment.md` — Kangaroo-Electron packaging, .webhapp bundling, CI/CD, versioning
- `WindTunnel.md` — performance and load testing reference using the wind-tunnel framework
- `Workflows/DesignDataModel.md` — DHT entry/link type design workflow
- `Workflows/Scaffold.md` — new project and domain scaffolding workflow
- `Workflows/ImplementZome.md` — full CRUD zome implementation workflow
- `Workflows/DesignAccessControl.md` — capability grants and admin patterns workflow
- `Workflows/PackageAndDeploy.md` — Kangaroo-Electron and CI/CD workflow
- `Workflows/ReviewZome.md` — guided code review checklist for coordinator and integrity zomes
- `docs/requirements.md` — v1 functional and non-functional requirements
- `docs/roadmap.md` — v1/v2/v3 vision and sub-skill roadmap
- Agent Skills Open Standard v1 compliance — YAML frontmatter, metadata block, and standard routing table in `SKILL.md`
- Multi-platform installation section in `README.md` covering Claude Code, GitHub Copilot, Cursor, Augment, and Codex
- DeepWiki badge in `README.md`

### Changed

- Repository renamed from `holochain-claude-skill` to `holochain-agent-skill`; all internal references updated
- All occurrences of "Claude Skill" replaced with "agent skill" for platform neutrality
- Clone URL updated to the canonical GitHub repository

[0.2.0]: https://github.com/Soushi888/holochain-agent-skill/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Soushi888/holochain-agent-skill/releases/tag/v0.1.0

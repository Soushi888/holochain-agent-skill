# Troubleshooting

Keyed on the literal text the compiler, conductor or CLI prints. Search this page for the error you actually saw.

Entries marked **(verified)** were reproduced on Holochain 0.7.0 while building this skill's example hApp. The rest are drawn from the official 0.6 to 0.7 upgrade guide and the release CHANGELOG.

---

## Build and compile

| Error text | Cause | Fix |
|---|---|---|
| `The wasm32-unknown-unknown targets are not supported by default; you may need to enable the "wasm_js" configuration flag` **(verified)** | Building zomes without the getrandom backend flag. The error names `getrandom`, not Holochain, so it reads like a dependency problem | `RUSTFLAGS='--cfg getrandom_backend="custom"' cargo build --release --target wasm32-unknown-unknown`. `npm run build:zomes` sets this for you |
| `cannot find type EntryCreationAction in this scope` | 0.6 code on 0.7 | `TypedAction<EntryCreationData>`. See `patterns.md` |
| `no variant named StoreEntry found for enum FlatOp` | 0.6 FlatOp names | `CreateEntry`. Full rename table in `patterns.md` |
| `no variant named RegisterCreateLink` / `RegisterDeleteLink` | Both folded into one variant in 0.7 | `FlatOp::Link(OpLink::CreateLink { .. })` |
| `no method named author found` on an action struct | The per-variant action structs are gone | `action.author()`, or `action.header.author`. Accessors exist on both `Action` and `TypedAction<D>` |
| `cannot move out of dereference` on a `TypedAction` field | `TypedAction<D>` derefs to its data; you cannot move through a deref | Use `.data` explicitly: `action.data.target_address.into_action_hash()` |
| `unresolved import holochain_zome_types::action::Action` | Crate-root and module re-exports were removed in 0.7 | Import from a prelude: `holochain_zome_types::prelude::Action`. Zomes importing only `hdi::prelude` / `hdk::prelude` are unaffected |
| `feature sqlite-encrypted does not exist` | Renamed in 0.7 | `encryption` |
| `feature wasmer_sys does not exist` | Renamed in 0.7 | `wasmer-sys-cranelift` |
| `feature transport-iroh does not exist` | Removed; iroh is compiled in unconditionally | Drop it from the feature list |
| Build fails looking for `perl` | A holochain build dependency needs it on PATH, usually surfacing only when building a Sweettest suite | Add `perl` to the `packages` list in `flake.nix` |
| `non-exhaustive patterns: AdminRequest::DumpOpTimings { .. } not covered`, raised **inside the `holochain` crate itself** **(verified)** | Version skew: the `holochain` crate is pinned to a `0.7.0-rc` while `holochain_conductor_api` resolves to stable `0.7.0`, which added the `DumpOpTimings` variant the rc does not handle. `hc scaffold` 0.700.0-rc emits exactly this combination | Pin `holochain` to stable `0.7.0` in `[workspace.dependencies]`, then `cargo update -p holochain`. Never leave the scaffolder's rc pins in place |

---

## Scaffolding

| Symptom | Cause | Fix |
|---|---|---|
| `Integrity zome "<name>" was not found in dna "<dna>"` **(verified)** | `--zome` takes the integrity crate's **package** name, not the directory name. `hc scaffold zome posts` creates directory `posts` with package `posts_integrity` | Pass `--zome posts_integrity` |
| Scaffolded `flake.nix` says `ref=main` **(verified)** | `hc scaffold` 0.700.0-rc emits `main`, and holonix `main` tracks the 0.8 dev line | Change to `ref=main-0.7` after scaffolding, then `nix flake update` |
| Scaffolded `flake.nix` says `nodejs_22` **(verified)** | Same stale template | Change to `nodejs_24` | <!-- legacy-ok -->
| Scaffolded `Cargo.toml` pins `-rc` crates **(verified)** | The scaffolding CLI is itself an rc | Pin stable: `hdi = "=0.8.0"`, `hdk = "=0.7.0"` |
| `hc: command not found` inside `nix develop` | Wrong holonix branch, or the shell did not rebuild | Check the `ref` in `flake.nix`, then `nix flake update && nix develop` |

---

## Conductor startup

| Error / symptom | Cause | Fix |
|---|---|---|
| Conductor exits immediately after a 0.7 upgrade | `NetworkConfig` rejects unknown fields rather than ignoring them | Remove `signal_url` and `webrtc_config`. Move `request_timeout_s` under `network`. Rename `db_sync_strategy` to `db_sync_level` (`Full`/`Normal`/`Off`; old `Resilient` maps to `Normal`, `Fast` to `Off`). Remove `chc_url` |
| Conductor cannot read existing databases | 0.7 renamed its databases and there is no migration path | `hc sandbox clean`. Expected, not a bug |
| Peers never connect after upgrading | DNA hashes changed in 0.7 even for otherwise identical DNAs, so you are on a new network | Everyone must be on the same build. Republish the DNA hash to your users |
| `hc sandbox` rejects the network type | Only `mem` and `quic` remain; `webrtc` is gone with tx5 | Update scripts passing `webrtc` |
| App manifest rejected for an unrecognised field | App and web-app manifests now reject unknown fields | Remove stray or misspelled keys. `manifest_version` is `'0'` |

---

## Validation

| Symptom | Cause | Fix |
|---|---|---|
| Validation passes locally, fails for other agents | Non-deterministic validation: a DHT read, `agent_info()`, `sys_time()`, or `get_init_properties()` | Validation may only inspect the op and what `must_get_*` returns. See `patterns.md` |
| A progenitor check works for the installer and nobody else | Reading `init_properties` instead of `modifiers.properties`. Init properties are conductor-local and invisible to other peers | Use `dna_info().modifiers.properties`. See `progenitor.md` |
| An entry fails to deserialize after a schema change | A field was added without `#[serde(default)]` | `Option<T>` alone is not sufficient. Add `#[serde(default)]` |
| `WrongActionError` from a narrowing conversion | The action was not the variant sys validation guarantees | Propagate with `?`, do not return `Invalid`. It is a fault, not bad author data |

---

## Testing

| Symptom | Cause | Fix |
|---|---|---|
| Cross-agent read returns `None` intermittently | Missing consistency wait | `await_consistency(&[&alice_cell, &bob_cell]).await.unwrap()` before every cross-agent read. `await_consistency_s(n, ..)` for a custom timeout |
| Suites over roughly 8 tests hang or flake | Too many in-process conductors at once | `cargo test -- --test-threads 6` |
| `Conductor::install_app_with_manifest` not found | Moved behind a feature in 0.7 | Enable the `test_utils` feature |
| `mock_network` not found | Removed from `holochain_p2p` in 0.7 | Use `test_utils` directly |
| Inline zome tests fail to compile | Inline zome definitions are no longer embedded in `DnaDef`; closures live on `DnaFile`, and `InlineZome::uuid` became `InlineZome::hash` | Rework against the 0.7 inline zome API |

---

## Deployment

| Symptom | Cause | Fix |
|---|---|---|
| Kangaroo build uses the wrong conductor | Cloned the default branch | `git checkout main-0.7`. `main-0.7` pins holochain 0.7.0; `main-0.6` pins 0.6.3 |
| App will not start after a version bump | Kangaroo isolates data folders on minor and major bumps by design | Expected. Only patch bumps share a data folder |
| Windows MSI build fails | Special characters in `PRODUCT_NAME` | Alphanumerics and hyphens only |

See also `deployment.md`, `testing.md` and `scaffolding.md`, which point here rather than repeating these tables.

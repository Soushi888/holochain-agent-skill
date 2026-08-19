# Source Chain, Introspection and Utility Host Functions

Read from `hdk 0.7.0` (`src/chain.rs`, `src/info.rs`, `src/time.rs`, `src/random.rs`, `src/validation_receipt.rs`), `hdi 0.8.0` (`src/info.rs`) and `holochain_zome_types 0.7.0` (`src/query.rs`, `src/info.rs`, `src/validate.rs`).

This file covers reading your **own** chain and the ambient facts a zome call can see. Reading **another** agent's chain activity is `get_agent_activity()`, which lives in `patterns.md` alongside `must_get_agent_activity` and chain forks.

## `query()`: your own chain

```rust
pub fn query(filter: ChainQueryFilter) -> ExternResult<Vec<Record>>
```

Coordinator zomes only, and it reads the calling agent's source chain, never anyone else's. This is how you answer "what have I written" without maintaining an agent-to-entry link index for your own data.

```rust
use hdk::prelude::*;

#[hdk_extern]
pub fn my_recent_posts(_: ()) -> ExternResult<Vec<Record>> {
    query(
        ChainQueryFilter::new()
            .entry_type(UnitEntryTypes::Post.try_into()?)
            .include_entries(true)
            .descending(),
    )
}
```

### `ChainQueryFilter`

Six fields, all defaulted, so `ChainQueryFilter::new()` means "every record, ascending, no entries".

| Field | Type | Meaning |
|---|---|---|
| `sequence_range` | `ChainQueryFilterRange` | Which slice of the chain. Default `Unbounded` |
| `entry_type` | `Option<Vec<EntryType>>` | Keep only these entry types |
| `entry_hashes` | `Option<HashSet<EntryHash>>` | Keep only these entry hashes |
| `action_type` | `Option<Vec<ActionType>>` | Keep only these action types |
| `include_entries` | `bool` | Load entry content, not just actions. Default `false` |
| `order_descending` | `bool` | Default is ascending. `.descending()` flips it |

**Building the `entry_type` argument.** `#[hdk_entry_types]` expands to include `hdk_entry_types_name_registration`, which generates both `impl TryFrom<UnitEntryTypes> for EntryType` and `impl TryFrom<UnitEntryTypes> for AppEntryDef`. Both impls are emitted by `hdk_derive`, in `hdk_derive-0.7.0/src/entry_types_name_registration.rs` (the `EntryType` one at line 184), not by `hdi`. They exist only in expanded code, so grepping `hdi` for them finds nothing. Either form works, and the target type decides which impl is used:

```rust
.entry_type(UnitEntryTypes::Post.try_into()?)                    // -> EntryType
.entry_type(EntryType::App(UnitEntryTypes::Post.try_into()?))    // -> AppEntryDef, then wrapped
```

Prefer the first. Both compile; the second only spells out what the first infers.

Builder methods: `sequence_range`, `entry_type`, `entry_hashes`, `action_type`, `include_entries`, `ascending`, `descending`. There are also in-memory helpers for when you already hold records: `filter_records`, `filter_actions` and `disambiguate_forks`.

### `query()` returns history, not current state

This is the trap that makes `query()` look like a cheap replacement for link-following, and it is not one. The source chain is a log of what you wrote, in the order you wrote it. Nothing in it resolves an update chain or hides a deletion.

**Updates.** `UpdateData` carries its own `entry_type` and an `entry_hash` pointing at the **new** content, so an `Update` matches the same `entry_type` filter its `Create` did. A query filtered only by entry type therefore returns the original and every revision as separate records, in chain order, with nothing marking which supersedes which.

```rust
// "Posts I authored", original content only. An edited post returns its FIRST version.
.entry_type(UnitEntryTypes::Post.try_into()?)
.action_type(ActionType::Create)

// Every version of every post, original and revisions, as separate records.
.entry_type(UnitEntryTypes::Post.try_into()?)
```

Pick deliberately, and know which one you asked for. Neither is "my posts as they stand now".

**Deletions are worse, because they are silent.** `DeleteData` holds only `deletes_address` and `deletes_entry_address`. It has **no** `entry_type` field, so a `Delete` action can never match an entry-type filter. A deleted post's `Create` record still comes back, and the result carries no signal that a later action removed it.

So a chain query cannot, on its own, tell you that something was deleted. You would have to query `ActionType::Delete` separately and reconcile the addresses yourself.

**If you need current state, follow the update links,** as `patterns.md` describes. Use `query()` when you genuinely want authorship history: what this agent wrote, when, in what order. The source chain is a history, not a view.

`include_entries(false)` is the default for a reason. Actions are small and entries are not. If you only need hashes or timestamps, leave entries off.

### `ChainQueryFilterRange` and the efficiency cliff

```rust
pub enum ChainQueryFilterRange {
    Unbounded,                              // default
    ActionSeqRange(u32, u32),               // inclusive start, inclusive end
    ActionHashRange(ActionHash, ActionHash),
    ActionHashTerminated(ActionHash, u32),  // this hash and N preceding records
}
```

The choice matters more than it looks, and the source spells out why:

- **`Unbounded`** is equivalent to `ActionSeqRange(0, u32::MAX)`.
- **`ActionSeqRange`** is ambiguous over forked histories. If the chain forked, more than one record can share a sequence number and the filter has no way to pick one, so all matching records come back. The `entry_type` and `action_type` filters are applied inside the database query, which makes this variant reasonably efficient.
- **The hash-bounded variants** resolve forks correctly, because naming a specific action hash names a specific branch. The cost: to do that, all relevant records must be loaded and the chain reconstructed in memory before any other filter is applied. The source says this "may be significantly less efficient than other query types".

So: sequence ranges are fast and fork-ambiguous, hash ranges are fork-correct and slow. Pick deliberately. `ActionHashTerminated(hash, 0)` returns just that one record.

## Cell introspection

Four host functions, each answering a different question. Two live in `hdi` (available in integrity code) and two in `hdk` (coordinator only).

| Function | Crate | Answers |
|---|---|---|
| `dna_info()` | `hdi` | Which DNA am I, with what modifiers |
| `zome_info()` | `hdi` | Which zome am I, with what types in scope |
| `agent_info()` | `hdk` | Who am I, and where is my chain head |
| `call_info()` | `hdk` | Who called me, how, and under what grant |

### `dna_info()` and `zome_info()`

```rust
pub struct DnaInfoV2 {
    pub name: String,
    pub hash: DnaHash,
    pub modifiers: DnaModifiers,   // network_seed, properties, origin_time...
    pub zome_names: Vec<ZomeName>,
}
pub type DnaInfo = DnaInfoV2;

pub struct ZomeInfo {
    pub name: ZomeName,
    pub id: ZomeIndex,
    pub properties: SerializedBytes,
    pub entry_defs: EntryDefs,
    pub extern_fns: Vec<FunctionName>,
    pub zome_types: ScopedZomeTypesSet,
}
```

`dna_info().modifiers.properties` is the deploy-time configuration channel: it is part of the DNA hash, identical for every agent, and readable from validation. That is what makes it the right home for a progenitor key. See `progenitor.md`, and `migration.md` for why `init_properties` is a different and non-interchangeable mechanism.

Both are callable from `validate()` and from `genesis_self_check`, because both are deterministic per DNA.

### `agent_info()` and the scratch space trap

```rust
pub struct AgentInfo {
    /// The current agent's pubkey at genesis.
    /// Always found at index 2 in the source chain.
    pub agent_initial_pubkey: AgentPubKey,
    pub chain_head: (ActionHash, u32, Timestamp),
}
```

`chain_head` reflects the chain **including uncommitted writes made earlier in this same zome call**, because those live in the call's scratch space. Call `create_entry` then `agent_info()` and the head has already moved, even though nothing has been persisted or published yet, and even though the call may still fail and roll everything back.

Never use `agent_info()?.chain_head` as a stable "where was I when this call started" marker. Use `call_info()?.as_at` for that.

`agent_info()` is a coordinator function. It is **not** callable from `validate()`: validation runs on other agents' machines, where "who am I" is a different question with a non-deterministic answer.

### `call_info()`

```rust
pub struct CallInfo {
    /// The provenance identifies the agent who made the call.
    /// This is the author of the chain for local calls, and the assignee of a capability for remote calls.
    pub provenance: AgentPubKey,
    pub function_name: FunctionName,
    /// Chain head as at the call start.
    /// This will not change within a call even if the chain is written to.
    pub as_at: (ActionHash, u32, Timestamp),
    pub cap_grant: CapGrant,
}
```

Two things here that nothing else gives you:

- **`provenance`** is the caller, which for a `call_remote` is the remote agent, not you. This is the field to check when a function should behave differently for remote callers. Comparing `provenance` against `agent_info()?.agent_initial_pubkey` is the "was this called locally" test.
- **`cap_grant`** is the grant that authorized this call. A function can inspect how it was reached, which is how you distinguish an unrestricted call from one that presented a specific secret. See `access-control.md`.

`as_at` is the honest chain head for the call: fixed at entry, unmoved by writes during the call.

## Utility host functions

### `sys_time()`

```rust
pub fn sys_time() -> ExternResult<Timestamp>
```

The host's wall clock, in a coordinator zome. **Forbidden in validation**, along with everything else non-deterministic: a validator running your `validate()` next week must reach the same verdict as one running it now.

When an entry needs a timestamp that validation can check, do not put `sys_time()` in the entry. The action header already carries a timestamp, and validation can read it from `action.header().timestamp`.

### `random_bytes()`

```rust
pub fn random_bytes(number_of_bytes: u32) -> ExternResult<Bytes>
```

Randomness from the host. Two caveats worth stating out loud: it is not seedable or repeatable, so nothing that consumes it can be replayed deterministically, and it is not usable in validation for the same reason as `sys_time()`. It is the right tool for a nonce or a cap secret, and the wrong tool for anything a validator must reproduce.

### Tracing

`hdk` wires the standard `tracing` macros through to the host, so `trace!`, `debug!`, `warn!` and `error!` work inside wasm. Two limits from the HDK documentation:

- Spans do **not** work. `#[instrument]` will likely panic your wasm.
- Filtering is by the `WASM_LOG` environment variable, which behaves exactly like `RUST_LOG` does for the conductor.

See `debugging.md` for how to actually read that output.

## Validation receipts

```rust
pub fn get_validation_receipts(
    input: GetValidationReceiptsInput,
) -> ExternResult<Vec<ValidationReceiptSet>>
```

After you author an action it becomes several DHT ops, each validated by other agents, each returning a signed receipt. This function reports what came back, grouped by op:

```rust
pub struct ValidationReceiptSet {
    pub op_hash: DhtOpHash,
    pub op_type: String,          // informational only
    pub receipts_complete: bool,  // did this op reach the required receipt count
    pub receipts: Vec<ValidationReceiptInfo>,
}

pub struct ValidationReceiptInfo {
    pub validation_status: ValidationStatus,
    pub validators: Vec<AgentPubKey>,
}
```

Usage, from the HDK's own example:

```rust
let receipts = get_validation_receipts(GetValidationReceiptsInput::new(action_hash))?;
let count = receipts
    .into_iter()
    .filter(|set| set.op_type == "AgentActivity")
    .flat_map(|set| set.receipts)
    .count();
```

**The constraint that decides whether you can use this:** receipts only exist for actions authored on the **same conductor**. Not necessarily the same agent, but the same conductor. Asking about someone else's action returns nothing, and that nothing is indistinguishable from "not validated yet".

Practical use is a "your post has been seen by N validators" indicator, or a test that waits for `receipts_complete` instead of sleeping. It is the closest thing to a per-action propagation signal that a zome can get.

## Related

- `patterns.md` for `get_agent_activity`, `must_get_*` and chain forks
- `debugging.md` for reading trace output and conductor state
- `progenitor.md` for the DNA-properties pattern that `dna_info()` serves
- `access-control.md` for `CapGrant` and what `call_info().cap_grant` tells you

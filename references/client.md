# Holochain TypeScript Client

## Package Version

```
@holochain/client   ^0.21.0   (Holochain 0.7 / hdk 0.7.x / hdi 0.8.x)
```

Holochain 0.7 changed the client surface. If you are porting from 0.20.x, read [Migrating from 0.20.x](#migrating-from-020x) first.

---

## Connection Setup

```typescript
import { AppWebsocket, AdminWebsocket } from "@holochain/client";

// App connection. The client is bound to the app it connects to, so there is
// no installed-app-id argument and no separate agent-aware class.
const client = await AppWebsocket.connect();

// Explicit URL and token, e.g. when the conductor is not discovered from env:
const client = await AppWebsocket.connect({
  url: new URL(`ws://localhost:${process.env.HC_PORT}`),
  token: authToken,
});

// Admin connection (test harnesses, installers, tooling — not app code):
const admin = await AdminWebsocket.connect({
  url: new URL(`ws://localhost:${process.env.HC_ADMIN_PORT}`),
});
```

> `AppAgentWebsocket` no longer exists. It was merged into `AppWebsocket`, which now carries the cell context itself.

---

## callZome Pattern

```typescript
const record = await client.callZome({
  role_name: "my_dna",
  zome_name: "my_zome",
  fn_name: "create_my_entry",
  payload: { title: "New Entry", status: "Active" },
});
```

`role_name` resolves the cell from the app manifest, which is what app code should use. Pass `cell_id` instead only when addressing a specific cloned cell.

---

## Actions: the header / data split

Holochain 0.7 split every action into a `header` holding the fields all actions share and a `data` payload holding the rest. The same split applies on the JavaScript side, and `SignedActionHashed` is **no longer generic**, because the per-variant action types no longer exist.

```typescript
import type { SignedActionHashed, ActionHash, AgentPubKey, Timestamp } from "@holochain/client";
import { encodeHashToBase64 } from "@holochain/client";

// Common fields live under .header
const author = encodeHashToBase64(action.hashed.content.header.author);
const createdAt = action.hashed.content.header.timestamp;

// Action-specific fields live under .data
const entryHash = action.hashed.content.data.entry_hash;
```

The `Create`, `Update`, `Delete`, `CreateLink` and `DeleteLink` types are no longer exported, so signal types lose their type parameter:

```typescript
export type MyAppSignal =
  | { type: "EntryCreated"; action: SignedActionHashed; app_entry: EntryTypes }
  | { type: "EntryUpdated"; action: SignedActionHashed; original_action_hash: ActionHash }
  | { type: "LinkCreated"; action: SignedActionHashed; link_type: string };
```

---

## Signal Subscription

```typescript
client.on("signal", (signal) => {
  if (signal.type !== "App") return;   // ignore system signals

  const { zome_name, payload } = signal.value;
  if (zome_name === "my_zome") handleMyZomeSignal(payload as MyAppSignal);
});

function handleMyZomeSignal(payload: MyAppSignal) {
  switch (payload.type) {
    case "EntryCreated":
      // refresh list
      break;
    case "EntryUpdated":
      // update one item in the store
      break;
  }
}
```

The payload shape mirrors the Rust `Signal` enum, which uses `#[serde(tag = "type")]`. See `patterns.md` for the emitting side.

---

## Type Utilities

```typescript
import { decodeHashFromBase64, encodeHashToBase64, type Record } from "@holochain/client";
import { decode } from "@msgpack/msgpack";

// Hash serialisation, for URLs and localStorage
const hashString = encodeHashToBase64(actionHash);
const hashBack = decodeHashFromBase64(hashString);

// Decode an entry out of a Record
function decodeEntry<T>(record: Record): T {
  if (!("Present" in record.entry)) {
    throw new Error("Expected a Present entry");
  }
  return decode(record.entry.Present.entry) as T;
}

// The action hash of a Record
function getActionHash(record: Record) {
  return record.signed_action.hashed.hash;
}
```

---

## Network Stats

```typescript
import { type ApiTransportStats } from "@holochain/client";

const stats: ApiTransportStats = await client.dumpNetworkStats();
const connected = stats.transport_stats.connections.length;
const direct = stats.transport_stats.connections.filter((c) => c.is_direct).length;
```

Both the app and admin clients return the same `ApiTransportStats` type now, nesting the transport figures under `transport_stats` and adding `blocked_message_counts`. The per-connection `is_webrtc` flag is now `is_direct`, since WebRTC is gone and iroh over QUIC is the only transport.

---

## Migrating from 0.20.x

| 0.20.x | 0.21.0 |
|---|---|
| `AppAgentWebsocket.connect(url, appId)` | `AppWebsocket.connect()` |
| `SignedActionHashed<Create>` | `SignedActionHashed` |
| `action.hashed.content.author` | `action.hashed.content.header.author` |
| `action.hashed.content.timestamp` | `action.hashed.content.header.timestamp` |
| `import { Create, CreateLink, ... }` | no longer exported; remove them |
| `TransportStats` | `ApiTransportStats` |
| `stats.connections` | `stats.transport_stats.connections` |
| `connection.is_webrtc` | `connection.is_direct` |
| `signalingServerUrl` in `ConnectionServices` | `relayServerUrl` |

---

## Environment Variables

```
HC_PORT=8888           # conductor app WebSocket port
HC_ADMIN_PORT=9000     # admin port (conductor management)
VITE_HC_PORT=8888      # Vite prefix, for browser access
```

---

## Framework Integration

The patterns above are framework-neutral. For stack-specific wiring:

- Svelte 5 runes stores — `frameworks/svelte.md`
- Effect-TS typed errors and timeouts — `frameworks/effect.md`

Neither is required. A React, Vue or vanilla app uses the client exactly as shown above.

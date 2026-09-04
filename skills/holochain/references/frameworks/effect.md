# Effect-TS Integration

Optional. The framework-neutral client surface is in `../client.md`; nothing here is required to use Holochain from TypeScript.

Effect earns its place when zome calls need typed errors, timeouts and retries as data rather than as `try`/`catch` scattered through the UI. On a small app it is overhead.

---

## Typed zome call

```typescript
import { Effect, pipe, Data } from "effect";
import type { AppWebsocket, CallZomeRequest } from "@holochain/client";

export class ZomeCallError extends Data.TaggedError("ZomeCallError")<{
  readonly fnName: string;
  readonly cause: unknown;
}> {}

export class ZomeTimeoutError extends Data.TaggedError("ZomeTimeoutError")<{
  readonly fnName: string;
}> {}

export function callZome<T>(client: AppWebsocket, req: CallZomeRequest) {
  return pipe(
    Effect.tryPromise({
      try: () => client.callZome(req) as Promise<T>,
      catch: (cause) => new ZomeCallError({ fnName: req.fn_name, cause }),
    }),
    Effect.timeoutFail({
      duration: "10 seconds",
      onTimeout: () => new ZomeTimeoutError({ fnName: req.fn_name }),
    }),
  );
}
```

`timeoutFail` gives a distinct error type rather than Effect's generic `TimeoutException`, so callers can discriminate on `_tag` without unwrapping a cause chain.

---

## Using it

```typescript
const program = pipe(
  callZome<Record[]>(client, {
    role_name: "my_dna",
    zome_name: "my_zome",
    fn_name: "get_all_my_entries",
    payload: null,
  }),
  Effect.map((records) => records.map(decodeEntry<MyEntry>)),
  Effect.catchTag("ZomeTimeoutError", () => Effect.succeed([])),
);

const entries = await Effect.runPromise(program);
```

---

## Retrying transient network failures

A zome call can fail because a peer was briefly unreachable. That is worth retrying; a validation failure is not.

```typescript
import { Schedule } from "effect";

const withRetry = pipe(
  callZome<Record>(client, req),
  Effect.retry(
    Schedule.exponential("200 millis").pipe(
      Schedule.compose(Schedule.recurs(3)),
    ),
  ),
);
```

Retry only what is genuinely transient. Retrying a call that failed validation just fails four times more slowly, and retrying a create can double-write if the first attempt actually landed.

---

## Where this fits

Keep Effect at the service boundary. Stores and components are easier to read when they receive plain values, so run the Effect at the edge and hand the result on.

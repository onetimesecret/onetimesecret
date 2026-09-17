---
id: "046"
status: proposed
title: "ADR-046: Bootstrap State Ordering Contract"
---

## Status

Proposed

## Date

2026-09-17

## Context

The client receives complete bootstrap state through two paths: the hydration
payload embedded in rendered HTML and later responses from `GET /bootstrap/me`.
Those snapshots can describe authentication, customer, configuration, and
other state that must remain internally consistent. If overlapping or delayed
responses are applied in arrival order, an older response can overwrite newer
state. Applying only part of a rejected response can also leave stores with a
combination of values that the server never produced as one snapshot.

A wall-clock datetime cannot provide a total order. Snapshots can have equal
timestamps, clocks can move backward, and workers can be unsynchronized. A
single installation-wide sequence would order snapshots across workers, but
exposing consecutive values would also reveal how many snapshots the
installation served between two observations. The client does not need that
global order: it only compares snapshots delivered to its own browser session.

The project already has a per-session storage primitive for this scope.
`Onetime::SessionSidecar` stores registered fields under independent
`sidecar:<sid>:<field>` Redis string keys, clamps their lifetime to the session,
and removes them through the session cleanup path. Its absence-is-safe
admission rule fits an ordering watermark because a missing value grants
nothing: snapshot construction fails or the client retains its last accepted
state.

## Decision

Every complete bootstrap payload will include these ordering fields through
both the HTML hydration payload and `GET /bootstrap/me`:

- `snapshot_epoch`: an opaque, unpredictable identifier for the current
  session-ID lifetime;
- `snapshot_version`: the positive sequence number within that epoch, encoded
  as a canonical decimal string; and
- `snapshot_generated_at`: the server generation time, used only for age and
  diagnostics.

The shared Zod/Rhales bootstrap schema will require and validate all three
fields. `snapshot_epoch` will be 32 lowercase hexadecimal characters.
`snapshot_version` will match `^[1-9][0-9]*$` and will never be encoded as a
JSON number, avoiding JavaScript's integer precision limit. The client will
compare validated versions with `BigInt`.

`snapshot_generated_at` will use fixed-width UTC RFC 3339 with exactly six
fractional digits:

```text
YYYY-MM-DDTHH:mm:ss.ssssssZ
```

For example, `2026-09-17T17:28:59.123456Z` is valid. This datetime is
non-normative: it will not decide whether a snapshot is newer. Clock rollback
or skew will produce a structured diagnostic but will not override the epoch,
version, or request-generation decision.

### Server allocation

The server will allocate the three fields once for each complete snapshot,
after authentication resolution:

1. It will derive `snapshot_epoch` from the current session ID with a
   domain-separated HMAC-SHA256 keyed by the application secret, truncated to
   128 bits and encoded as lowercase hexadecimal. The raw bearer session ID
   will never enter the payload. The same SID therefore produces a stable,
   opaque epoch, while session renewal produces a different epoch without
   migration state.
2. `snapshot_version` will use one registered, explicit-use sidecar string key
   bound to the current session ID. It is not merged into the Rack session
   blob.
3. One Redis Lua operation will increment that key with `INCR`, refresh its
   TTL, and return the version atomically. Because the sidecar field is a Redis
   string, this uses `INCR`, not `HINCRBY`.
4. The version TTL will be clamped to the authoritative session lifetime and
   the key will be covered by the existing exact-name sidecar purge.
5. The version will be returned to the payload as a decimal string.
6. Allocation failure will fail construction of the complete snapshot. The
   server will never label an unversioned payload as complete. This does not
   change the session middleware's best-effort failure posture: a snapshot
   allocation failure must not make an otherwise valid session write fail.

An epoch is deliberately scoped to one session ID. A session-ID renewal starts
a new epoch instead of attempting to migrate or compare the old sidecar
counter. This avoids exposing an installation-wide counter and keeps the
ordering state within the sidecar's existing ownership and cleanup boundary.

### Client acceptance

The HTML hydration snapshot establishes the initially accepted epoch and
version. A full page load has no preceding client watermark and accepts its
validated hydration pair as the start of the stream.

Within the accepted epoch, the client will accept a complete snapshot only
when both conditions hold:

1. its `snapshot_version` is strictly greater than the accepted version; and
2. its client request generation is still current.

Equal or lower versions will be ignored as a unit. A rejected snapshot must
not update the bootstrap store, its service-level mirror, authentication
state, diagnostics context, or any other dependent store.

An unexpected epoch change from an ordinary refresh will be rejected. A
response may establish a new epoch only when it belongs to the current
authentication-mutation generation. Accepting that transition atomically
replaces the prior epoch and version. Every later response from the prior
epoch is rejected, regardless of its version.

Once the client has accepted an ordered snapshot, it will reject every later
complete snapshot with a missing or malformed epoch, version, or generation
timestamp. This is a downgrade guard; invalid ordering metadata cannot make
the client forget or bypass its accepted watermark. Local state patches are
not complete server snapshots and never advance or replace the watermark.

### Refresh coordination

One shared refresh coordinator will own ordinary bootstrap refreshes and allow
at most one ordinary refresh request in flight. It will assign a monotonically
increasing client request generation to operations that exceptionally overlap.

Authentication mutations will cancel an older refresh when possible and will
always invalidate its request generation. Only the current authentication
generation may establish a new epoch. The acceptance check and commit of all
snapshot-derived state will form one transaction at the client coordination
boundary; no consumer may apply a complete response independently before that
decision.

Structured diagnostics will record rejected epochs or versions, invalidated
request generations, allocation failures, and clock regressions. Diagnostics
will include ordering metadata but not bootstrap payload contents. A rejected
snapshot leaves the last accepted state intact.

This contract claims a server-authoritative total order within each session
epoch. It does not claim or require a global order among snapshots delivered
to unrelated sessions. Current client request generations authoritatively
order the permitted transitions between epochs.

## Trade-offs

- **We lose:** A single scalar that appears to order every snapshot globally.
  Consumers must carry an epoch and version together, and authentication
  transitions have an explicit acceptance rule.
- **We gain:** Deterministic ordering across workers for one browser session
  without exposing installation-wide snapshot volume. Ordering state uses the
  project's existing session lifetime and cleanup boundary.
- **Risk:** Loss or premature expiry of the version key resets its sequence
  within the existing epoch. An ordinary refresh will reject the lower
  version, preserving state but requiring a full page load to establish a new
  initial watermark. TTL refresh and session-lifetime clamping must therefore
  be tested together.

## Consequences

Bootstrap consumers will distinguish complete snapshots from local patches.
Only complete snapshots participate in epoch, version, and request-generation
acceptance; local optimistic changes remain possible but cannot redefine
server order.

All refresh entry points, including periodic checks and refreshes following
authentication operations, will converge on one coordinator. Store updates
that currently occur outside the bootstrap-store update path will happen only
after the coordinator accepts the complete response.

Tests will cover epoch derivation, atomic version allocation, TTL refresh and
purge, schema validation, large decimal versions, hydration initialization,
strictly newer acceptance, atomic rejection of equal and lower versions,
ordinary rejection of unexpected epochs, authorized authentication epoch
transitions, missing or malformed metadata, non-advancing local patches,
overlapping request generations, authentication invalidation, allocation
failure, and non-normative clock-regression diagnostics.

## Related

- [Frontend Architecture](../architecture/frontend.md) — current hydration,
  bootstrap-store, and `GET /bootstrap/me` data flow
- `lib/onetime/session/sidecar.rb` — session-scoped storage, lifetime, and
  cleanup boundary
- `src/schemas/contracts/bootstrap.ts` — shared Zod/Rhales bootstrap contract
- `src/shared/stores/bootstrapStore.ts` — client bootstrap state boundary
- `src/shared/stores/authStore.ts` — periodic and authentication-related
  refresh entry points

## Implementation Notes

### Ordering alternatives considered and rejected (2026-09-17)

- **`snapshot_generated_at` as the watermark:** Rejected because a datetime
  cannot order equal timestamps, clock rollback, or unsynchronized workers.
  It remains useful only as snapshot-age and diagnostic metadata. Converting
  it through JavaScript `Date` was also rejected because that would discard
  the wire format's microsecond precision.
- **Redis `INFO stats` / `total_commands_processed`:** Rejected because it is
  an operational statistic covering every Redis command, is local to Redis
  process and topology state, can be reset, and would disclose unrelated
  production activity. It is not application ordering state.
- **An installation-wide consecutive `INCR`:** Rejected because a client could
  subtract two observed versions and learn how many snapshots the installation
  served between its requests. The client requires order only for its own
  stream.
- **Obfuscating a global counter:** Random offsets preserve differences, while
  random increments and order-preserving encodings still disclose traffic
  characteristics and add a custom protocol. They solve a scope problem the
  session-local design avoids.
- **A SID-bound counter without an epoch:** Rejected because session renewal or
  sidecar loss can reset the counter. A lower number alone cannot distinguish a
  valid new session stream from a stale response.
- **`HINCRBY` on the session:** Rejected because `session:<sid>` is an encrypted
  Redis string rather than a hash, and each `SessionSidecar` field is already
  its own Redis string. A counter-specific sidecar `INCR` preserves the current
  storage and cleanup model.

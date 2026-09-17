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
and removes them through the session cleanup path. Its key naming, lifetime
clamp, and cleanup fit an ordering watermark. Its value model does not: every
registered field is stored as a JSON or codec envelope, while an atomic counter
must be a bare Redis integer. The decision therefore adds a counter policy to
the registry instead of reusing the generic read and write API.

The ordering contract must not hide the state changes that the periodic
`GET /bootstrap/me` check exists to detect. Logout in another tab renews the
session ID. Session expiry and server-side revocation keep the session ID but
remove the session's sidecar keys. Each of these reaches the client as an
ordinary refresh whose ordering metadata does not continue the accepted
stream, and each must still take effect.

## Decision

Every complete bootstrap payload will include these ordering fields through
both the HTML hydration payload and `GET /bootstrap/me`:

- `snapshot_epoch`: an opaque, unpredictable identifier for the current
  session-ID lifetime;
- `snapshot_version`: the positive sequence number within that epoch, encoded
  as a canonical decimal string; and
- `snapshot_generated_at`: the server generation time, used only for age and
  diagnostics.

The shared Zod/Rhales bootstrap schema will validate the three fields as a
unit: all present and valid, or all absent. A `GET /bootstrap/me` response must
carry them. Absence is permitted only in a degraded hydration payload (see
allocation failure below). `snapshot_epoch` will be 32 lowercase hexadecimal
characters.
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
2. `snapshot_version` will use one registered sidecar key bound to the current
   session ID, under a new registry policy, `counter: true`. A counter field
   holds a bare Redis integer, not a JSON or codec envelope. It is not
   encrypted: it carries no secret, the payload publishes it, and its binding
   to the session is its key name. The generic `write`, `read`, and `consume`
   methods will raise for a counter field, because an envelope write would make
   every later `INCR` fail and an envelope read of an integer returns nil. Only
   the dedicated allocation method touches the key. The field is never merged
   into or externalized from the Rack session blob and does not warn on
   destroy.
3. One Redis Lua operation will allocate the version atomically. When the key
   exists it uses `INCR`. When the key is absent it seeds the key from Redis
   `TIME` as integer microseconds since the Unix epoch, written as an integer
   string and not in Lua's default exponent form. In both cases it sets the TTL
   and returns the version. Because the sidecar field is a Redis string, this
   uses `INCR`, not `HINCRBY`.
4. The seed is not a return to wall-clock ordering. Order within one key
   lifetime comes only from `INCR`. The seed makes a recreated counter start
   above every version the lost key issued. That holds while the session
   averages fewer than one million snapshots per second and the Redis clock has
   not moved back by more than the lost key's age. Expiry, eviction, or purge
   of the key within a live epoch is therefore invisible to the client.
5. Allocation runs inside a request whose session commit rewrites the blob to
   `expire_after`, so the key's TTL will be that authoritative lifetime, not
   the blob's remaining TTL at allocation time. The key will be covered by the
   existing exact-name sidecar purge. Only bootstrap requests refresh the key
   while every request extends the blob, so the key can still expire before a
   live session does; the seed covers that case.
6. The version will be returned to the payload as a decimal string.
7. Allocation failure includes a Redis error and a session ID that fails the
   sidecar `SID_FORMAT` guard. The allocation method will raise for both and
   will not return nil the way the generic API does. The server will never
   label an unversioned payload as ordered. The result depends on the path:
   - `GET /bootstrap/me` will fail with a retryable 503. The client treats it
     as a failed refresh: it retains its last accepted state and the failure
     counts toward the existing consecutive-failure limit.
   - The HTML hydration path has no last accepted state to fall back on, so
     the page will still render. Its payload will omit all three ordering
     fields and the server will record a diagnostic. The client starts
     unordered: it accepts the hydration payload as initial state with no
     watermark and schedules an immediate ordinary refresh. The first valid
     ordered snapshot on the current request generation establishes the
     watermark.
   - Neither case changes the session middleware's best-effort failure
     posture: an allocation failure must not make an otherwise valid session
     write fail.

An epoch is deliberately scoped to one session ID. A session-ID renewal starts
a new epoch instead of attempting to migrate or compare the old sidecar
counter. This avoids exposing an installation-wide counter and keeps the
ordering state within the sidecar's existing ownership and cleanup boundary.

### Client acceptance

The HTML hydration snapshot establishes the initially accepted epoch and
version. A full page load has no preceding client watermark and accepts its
validated hydration pair as the start of the stream.

Request generation decides staleness. A response whose client request
generation is no longer current is stale and will be ignored as a unit,
whatever its epoch or version. An ignored or rejected snapshot must not update
the bootstrap store, its service-level mirror, authentication state,
diagnostics context, or any other dependent store.

A response on the current request generation is the server's answer to the
newest request the client made. The client will classify it against the
accepted watermark:

1. **Accepted epoch, strictly greater version:** accepted.
2. **Accepted epoch, equal or lower version:** a version discontinuity. The
   snapshot is not applied. With a seeded counter this indicates a replayed
   response or a Redis clock regression across a key loss. The coordinator
   will record a diagnostic and issue one immediate refresh. A second
   consecutive discontinuity will force a full page load, which establishes a
   new watermark through hydration. The client never remains on rejected state
   indefinitely. `GET /bootstrap/me` will be served with
   `Cache-Control: no-store`.
3. **Retired epoch:** rejected, regardless of its version. The client will
   remember every epoch it has replaced for the lifetime of the page.
4. **New epoch**, neither accepted nor retired: the session the client was
   tracking no longer exists. The client will accept the snapshot atomically
   as the start of a new stream and retire the prior epoch and version. This
   happens in one of two ways:
   - On the current authentication-mutation generation the transition is
     expected.
   - On an ordinary refresh it is a session replacement: logout or login in
     another tab, or any other session-ID renewal outside this tab. The
     coordinator will first run the same session-scoped store teardown that
     logout uses, then commit the snapshot, and record a diagnostic. Ignoring
     the response would leave the tab presenting a session that no longer
     exists, with a stale CSRF token.

A snapshot is never rejected because it reports `authenticated: false`. An
accepted snapshot that changes `authenticated` from true to false drives the
existing logout flow. Session expiry and server-side revocation keep the
session ID, so they arrive under rule 1: the purged or expired counter reseeds
above the accepted version.

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
always invalidate its request generation. Only a response on the current
request generation may establish a new epoch; a stale response never can. The
acceptance check and commit of all
snapshot-derived state will form one transaction at the client coordination
boundary; no consumer may apply a complete response independently before that
decision.

Structured diagnostics will record rejected epochs or versions, version
discontinuities, session replacements, invalidated request generations,
allocation failures, degraded hydration payloads, and clock regressions.
Diagnostics will include ordering metadata but not bootstrap payload contents.
A rejected snapshot leaves the last accepted state intact.

This contract claims a server-authoritative total order within each session
epoch. It does not claim or require a global order among snapshots delivered
to unrelated sessions. Current client request generations authoritatively
order the permitted transitions between epochs.

## Trade-offs

- **We lose:** A single scalar that appears to order every snapshot globally.
  Consumers must carry an epoch and version together, and authentication
  transitions have an explicit acceptance rule. The sidecar registry gains a
  second value model, the bare-integer counter, beside its envelopes. An
  ordinary refresh can replace the session shown in a tab without any action
  in that tab.
- **We gain:** Deterministic ordering across workers for one browser session
  without exposing installation-wide snapshot volume. Ordering state uses the
  project's existing session lifetime and cleanup boundary.
- **Risk:** Reseeding depends on the Redis clock moving forward across a key
  loss. A regression larger than the lost key's age, for example after
  failover to a replica with a skewed clock, can produce a lower version
  within a live epoch. The client then takes the discontinuity path: one
  retry, then a full page load, which can discard unsaved form input. The
  seeded counter, TTL refresh, and discontinuity recovery must therefore be
  tested together.

## Consequences

Bootstrap consumers will distinguish complete snapshots from local patches.
Only complete snapshots participate in epoch, version, and request-generation
acceptance; local optimistic changes remain possible but cannot redefine
server order.

All refresh entry points, including periodic checks and refreshes following
authentication operations, will converge on one coordinator. Store updates
that currently occur outside the bootstrap-store update path will happen only
after the coordinator accepts the complete response.

Tests will cover epoch derivation, atomic version allocation, seeding and
reseeding after key loss, TTL refresh and purge, refusal of the generic
sidecar API for counter fields, schema validation of the fields as a unit,
large decimal versions, hydration initialization, degraded hydration and the
first ordered snapshot after it, a 503 from `GET /bootstrap/me` on allocation
failure, strictly newer acceptance, version discontinuity retry and forced
page load, rejection of retired epochs, session replacement on an ordinary
refresh, logout in another tab, session expiry and server-side revocation
reaching the client as `authenticated: false`, authorized authentication epoch
transitions, missing or malformed metadata, non-advancing local patches,
overlapping request generations, authentication invalidation, and
non-normative clock-regression diagnostics.

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
- **A SID-bound counter without an epoch:** Rejected because session renewal
  starts a new counter. A lower number alone cannot distinguish a valid new
  session stream from a stale response.
- **A counter that starts at 1:** Rejected because the key can expire or be
  purged while the epoch lives on. Session expiry and server-side revocation
  keep the session ID, and only bootstrap requests refresh the key's TTL. The
  restarted counter would sit below the accepted version, so the client would
  reject the `authenticated: false` response as a successful 200 and keep
  presenting the user as signed in.
- **Rejecting an unexpected epoch on an ordinary refresh:** Rejected because
  logout in another tab renews the session ID. The periodic check would ignore
  the one response that reports the logout, and the consecutive-failure limit
  would never fire because the request succeeded. Request generation already
  excludes stale responses, so a new epoch on the current generation is
  treated as a session replacement.
- **`HINCRBY` on the session:** Rejected because `session:<sid>` is an encrypted
  Redis string rather than a hash, and each `SessionSidecar` field is already
  its own Redis string. A counter-specific sidecar `INCR` preserves the current
  key naming, lifetime, and cleanup model. It does not fit the envelope value
  model, which is why the registry gains a counter policy.

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

Only a tab with a session refreshes. `authStore.checkWindowStatus` skips the
request when the tab is definitively unauthenticated and not awaiting MFA.
Anonymous page views are most of the traffic, and each already persists a
CSRF-bearing session. They have no stream to order. The session layer already
gates its per-session bookkeeping to authenticated sessions (`TrackMetadata`
in `write_session`), and this contract follows that precedent.

## Decision

A session is ordered when its loaded session state marks it authenticated or
awaiting MFA. `awaiting_mfa` may be sidecar-backed rather than present in the
serialized session blob. These are the sessions whose tabs refresh. Every
complete bootstrap payload for an ordered session will include these ordering
fields through both the HTML hydration payload and `GET /bootstrap/me`:

- `snapshot_epoch`: an opaque, unpredictable identifier for the current
  session-ID lifetime;
- `snapshot_version`: the positive sequence number within that epoch, encoded
  as a canonical decimal string; and
- `snapshot_generated_at`: the server generation time, used only for age and
  diagnostics.

The shared Zod/Rhales bootstrap schema will validate `snapshot_epoch` and
`snapshot_version` as a unit: both present and valid, or both absent. A
`GET /bootstrap/me` response for an ordered session must carry them. They are
absent for a session that is not ordered, for which the server allocates
nothing, and in a degraded hydration payload (see allocation failure below).
`snapshot_generated_at` is an optional string in the schema, so a missing or
malformed timestamp cannot fail the parse of a payload whose ordering pair is
valid; its format is checked separately (see below).

`snapshot_epoch` will be 32 lowercase hexadecimal characters.
`snapshot_version` will match `^[1-9][0-9]*$` and will never be encoded as a
JSON number, avoiding JavaScript's integer precision limit. The client will
compare validated versions with `BigInt`.

`snapshot_generated_at` will use fixed-width UTC RFC 3339 with exactly six
fractional digits:

```text
YYYY-MM-DDTHH:mm:ss.ssssssZ
```

For example, `2026-09-17T17:28:59.123456Z` is valid. This datetime is
non-normative: it will not decide whether a snapshot is newer or whether it is
applied. Clock rollback or skew will produce a structured diagnostic but will
not override the epoch, version, or request-generation decision. The format
binds the server. On the client, a missing or malformed value produces the
same kind of diagnostic and the snapshot's age is reported as unknown; the
snapshot is still classified by its epoch and version and applied if accepted.
A logout or a permission downgrade must not be discarded because a serializer
rendered three fractional digits instead of six.

### Server allocation

The server will allocate the epoch and version once for each Web Core request
that carries an ordered session. Allocation runs in Web Core middleware, after
the session is loaded and before the router invokes the authentication
strategy. The strategy resolves the customer record, the organization context
(`OrganizationLoader#load_organization_context`), and the authenticated
decision, and `OrganizationSerializer` emits the plan, entitlements, limits,
and role from that organization. Allocating any later would stamp state that
had already been read.

The version is a start stamp: a snapshot reflects every write committed before
its version was allocated. Accepting the highest version therefore never moves
the client behind the instant that version's request began. The session blob
is the one exception, because allocation needs the session ID and the
ordered-session check.

The middleware does not know whether the route will serialize a snapshot, so a
version can be allocated and never delivered. Versions are compared only as
strictly greater, so gaps are harmless.

The stamp does not order two snapshots whose requests overlap on the server.
Either one may carry the newer state. That case does not reach acceptance in
one tab: every request for a complete snapshot takes a request generation, so
the coordinator applies only responses whose request began after the previous
accepted response arrived, and discards the rest. The allocation steps are:

1. It will derive `snapshot_epoch` from the current session ID with a
   domain-separated HMAC-SHA256 keyed by the application secret, truncated to
   128 bits and encoded as lowercase hexadecimal. The raw bearer session ID
   will never enter the payload. With an unchanged application secret, the same
   SID produces a stable, opaque epoch; session renewal derives a new epoch
   without migration state.
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
   of the key within a live session is therefore invisible to the client.
5. Allocation runs inside a request whose session commit rewrites the blob to
   `expire_after`, so the key's TTL will be that authoritative lifetime, not
   the blob's remaining TTL at allocation time. The key will be covered by the
   existing exact-name sidecar purge. Only Web Core requests refresh the key
   while API requests also extend the blob, and Redis can evict the key, so it
   can be lost while the session lives; the seed covers that case.
6. The version will be returned to the payload as a decimal string.
7. The allocation method raises on failure; see allocation failure below.

An epoch is deliberately scoped to one session ID. A session-ID renewal starts
a new epoch instead of attempting to migrate or compare the old sidecar
counter. This avoids exposing an installation-wide counter and keeps the
ordering state within the sidecar's existing ownership and cleanup boundary.

#### Allocation failure {#allocation-failure}

Allocation failure includes a Redis error and a session ID that fails the
sidecar `SID_FORMAT` guard. The allocation method will raise for both and
will not return nil the way the generic API does. The middleware catches
the failure and records it for the request, so a route that serializes no
snapshot is unaffected. The server will never label an unversioned payload
as ordered. The result depends on the path:

- `GET /bootstrap/me` will fail with a retryable 503. The client retains
  its last accepted state and retries after the server's `Retry-After`,
  floored and capped like every other coordinator retry, with a
  five-second default. The failure does not count toward the
  consecutive-failure limit and never moves the tab to `unavailable`:
  it is a fault in ordering storage, not a verdict on the session, and
  counting it would withhold authority from every signed-in tab for the
  length of a Redis outage. The refresh resolves as
  `allocation-unavailable`, which callers treat as not applied.
- The HTML hydration path has no last accepted state to fall back on, so
  the page will still render. Its payload will omit the epoch and version
  and the server will record a diagnostic. The client starts unordered
  (see client acceptance below).
- Neither case changes the session middleware's best-effort failure
  posture: an allocation failure must not make an otherwise valid session
  write fail.

### Client acceptance

The HTML hydration snapshot establishes the initially accepted epoch and
version. A full page load has no preceding client watermark and accepts its
validated hydration pair as the start of the stream.

A hydration payload without the pair starts the tab unordered. An unordered
tab has no watermark and applies complete snapshots as the client does today,
until the first valid ordered snapshot on the current request generation
establishes one. If the hydration payload reports a session but carries no
pair, the client schedules one immediate ordinary refresh. That covers
degraded hydration and a request that authenticated the session after the
allocation middleware ran. Anonymous tabs are unordered and do not refresh.
This is also the behaviour against a server that predates this contract or
has been rolled back from it.

Request generation decides staleness. A response whose client request
generation is no longer current is stale and will be ignored as a unit,
whatever its epoch or version. An ignored or rejected snapshot must not update
the bootstrap store, its service-level mirror, authentication state,
diagnostics context, or any other dependent store.

Two principles govern a response on the current request generation:

- Ordering exists to stop stale state from replacing newer state. It must
  never stop the end of a session from reaching the tab.
- The client never stays on state it has refused to replace. Every response
  is applied, ends in a page load, or is retried once and then ends in a page
  load.

A tab with a watermark will classify the response in this order:

1. **Session ended:** the snapshot reports neither an authenticated nor an
   MFA-pending session. It is never rejected, whatever its ordering metadata,
   including none. Session expiry, server-side revocation, and logout in
   another tab all arrive this way.
   - On the current authentication-mutation generation it is the result of
     this tab's own logout. The client accepts it atomically, retires the
     prior epoch, and becomes unordered.
   - On an ordinary refresh the client does not apply it in place. It records
     a diagnostic, stops ordinary refreshes, and takes the forced page load
     path below.
2. **Session replaced:** the epoch is neither accepted nor retired. The
   client will retire the prior epoch and version.
   - On the current authentication-mutation generation the transition is
     expected. The client accepts the snapshot atomically as the start of a
     new stream.
   - On an ordinary refresh it is a login in another tab, possibly as a
     different customer, or any other session-ID renewal outside this tab. The
     client does not apply it in place. It records a diagnostic, stops
     ordinary refreshes, and takes the forced page load path below; hydration
     then starts the new stream.
3. **Accepted epoch, strictly greater version:** applied atomically.
4. **Anomaly:** anything else. That is an equal or lower version, a retired
   epoch, or a missing or malformed epoch or version on a snapshot that
   reports a session. The snapshot is not applied. The known causes are a
   replayed response, a Redis clock regression across a key loss, and a worker
   that predates this contract during a rolling deploy. The coordinator will
   record a diagnostic and issue one immediate refresh. A second consecutive
   anomaly takes the forced page load path below. The client will remember
   every epoch it has replaced for the lifetime of the page.

Applying an ended or replaced session in place was rejected because it would
depend on a complete teardown of session-scoped client state, and no such
teardown exists. `authStore.logout()` resets the auth store, the bootstrap
store's user state, the diagnostics actor context, and `sessionStorage`. It
resets no other Pinia store, and the hard logout paths in `useAuth` rely on
navigation to discard the rest. `checkWindowStatus` today applies
`authenticated: false` in place without calling `logout()`, so an expired
session leaves the customer's cached data on screen, and a login as a
different customer in another tab could leave the prior customer's. A page
load discards the JavaScript context, so it needs no teardown inventory.

### Response caching

`GET /bootstrap/me` must be served with `Cache-Control: no-store`. This is a
requirement of the contract, not an existing guarantee:
`Core::Controllers::Page#bootstrap_me` sets no `Cache-Control` header today.
A replayed response is one of the causes of an anomaly, and a
response without explicit freshness information may be stored and reused
heuristically by a browser or intermediary. The implementation will add the
header and a test that asserts it.

### Forced page load

An ended session, a replaced session, and a second consecutive anomaly all end
in `window.location.reload()`. A reload can discard input the user has not
submitted, such as a secret being typed, so the path follows the platform's
documented behaviour and guidance instead of a project-specific mechanism:

- A programmatic reload fires `beforeunload` like a user-initiated one. The
  browser does not prompt by itself. It shows its generic confirmation only
  when a `beforeunload` handler cancels the event and the document has sticky
  activation, meaning the user has interacted with the page (HTML Standard,
  "prompt to unload"; MDN).
- Views that hold unsubmitted input will therefore register a `beforeunload`
  listener through one shared composable. Following MDN, web.dev, and Chrome
  guidance, the listener is added only while unsubmitted input exists and
  removed once it is submitted or cleared, because a standing listener makes
  the page ineligible for the back/forward cache in Firefox. The handler calls
  `event.preventDefault()` and sets `returnValue = ''` for older browsers. The
  dialog text cannot be customized.
- Without sticky activation there is no prompt, and also no typed input to
  lose. A tab the user never touched reloads silently.
- Browsers do not report whether a `beforeunload` prompt was cancelled. Before
  calling `window.location.reload()`, the client must synchronously enter the
  stale-session state: ordinary refreshes remain stopped, no snapshot is
  applied, and a persistent notice states that the page must be reloaded. If
  the navigation proceeds, it discards that state. If the user cancels the
  prompt, the state remains visible and the client does not retry the reload.
  The user can copy their input and reload when ready.
- The client records the time of each forced page-load attempt in a per-tab
  `sessionStorage` marker. If another forced page load is demanded within one
  minute of the last, the client enters the stale-session state instead of
  reloading. This bounds a reload loop whatever its cause.
- `beforeunload` is not reliable on mobile platforms and is not a persistence
  mechanism. The platform's recommendation for preserving state is to save it
  on `visibilitychange`. This contract will not do that for secret content,
  because it would write unsubmitted secrets to browser storage. Where the
  browser skips the prompt, a forced page load can still discard input.

Only `DomainBrand.vue` has a `beforeunload` guard today. It installs its
listener when the component mounts and removes it on unmount; its handler
returns unless there are unsaved changes. It therefore does not yet meet this
contract's conditional-registration requirement. The secret creation form has
no guard, so the shared guard is new work for every view whose input this path
could discard.

#### Parked transition message {#parked-transition-ttl}

Before a forced page load for an ended or replaced session, the client parks
the kind of transition in `sessionStorage` so the reloaded page can tell the
user why it reloaded. `reload()` only requests a navigation; it does not
report whether the navigation happened, and a cancelled `beforeunload` prompt
leaves the park behind. Each park is therefore stamped with the time it was
written, and the reader discards one older than one minute. A real reload
consumes it within milliseconds. A successful commit also clears it, because
a reconciled tab no longer needs the reload to explain anything. The time
limit is what guarantees a stale message never appears on an unrelated later
page load; the clear on commit only makes that happen sooner.

### Downgrade guard

Once the client holds a watermark, a snapshot that reports a session but lacks
a valid epoch or version is an anomaly (rule 4). Invalid ordering metadata
cannot make the client forget or bypass its watermark. It cannot strand the
client either, because the anomaly path ends in a page load, and hydration
from a server without the contract starts the tab unordered. A snapshot that
reports no session is not a downgrade; it is rule 1.

The guard does not cover `snapshot_generated_at`, which orders nothing: a
missing or malformed generation timestamp is a diagnostic, not an anomaly.
Local state patches are not complete server snapshots and never advance or
replace the watermark.

### Refresh coordination

One shared refresh coordinator will own ordinary bootstrap refreshes and allow
at most one ordinary refresh request in flight. Every request for a complete
snapshot takes the next client request generation, and starting one
invalidates all earlier generations.

Authentication mutations will cancel an older refresh when possible and will
always invalidate its request generation. Only a response on the current
request generation may establish a new epoch; a stale response never can. The
acceptance check and commit of all snapshot-derived state will form one
transaction at the client coordination boundary; no consumer may apply a
complete response independently before that decision.

Structured diagnostics will record anomalies with their epoch and version,
ended sessions, session replacements, invalidated request generations,
allocation failures, degraded hydration payloads, missing or malformed
generation timestamps, and clock regressions. Diagnostics will include
ordering metadata but not bootstrap payload contents. A rejected snapshot
leaves the last accepted state intact.

This contract claims a server-authoritative total order of version
allocations within each session epoch, and that each snapshot reflects every
write committed before its allocation. It does not claim that two snapshots
built by overlapping requests are ordered by the state they carry. It does not
claim or require a global order among snapshots delivered to unrelated
sessions. Current client request generations authoritatively order the
permitted transitions between epochs.

### Caller contracts {#caller-contracts}

The coordinator decides what the tab believes. The contracts below bind the
code that acts on that decision: views and composables that navigate after
authentication, chrome that offers actions, error handlers that report a
rejected call, and the coordinator's own commit.

#### Auth completion {#auth-completion-caller-contract}

`refresh()` resolves to a `RefreshOutcome`: `applied`, `superseded`,
`failed`, `refused`, or `allocation-unavailable`. `setAuthenticated()`
returns that outcome instead of discarding it.

A caller that finishes a first-factor authentication POST and then navigates
to a destination derived from authority, such as `/mfa-verify` or the
dashboard, checks three independent conditions before navigating:

1. **The operation is still its own.** `superseded` means a newer
   coordinator run has already reconciled and owns the destination. The
   caller does nothing. This is success by delegation, not a failure.
2. **A snapshot was applied.** Any outcome other than `applied` means the
   tab has not verified the new session. The caller retries verification
   with an ordinary refresh, does not re-send the authentication POST, and
   does not navigate. After a short bounded retry it shows a retryable error.
3. **The resulting status matches the destination.** A caller heading to
   the dashboard does not navigate while the status is `mfa_pending`, and
   the reverse. It retries as in (2), and shows an error if the mismatch
   persists.

The retry targets verification because the authentication POST may be single
use: it can consume a nonce, a rate-limit slot, or a lockout counter.
Verification is idempotent and cheap. `src/shared/composables/authCompletion.ts`
implements the three checks for every caller. How a retryable completion
error is presented is not yet settled (#4501); each caller currently reuses the
error display it already has.

#### Authority and action gating {#authority-action-gating}

Each status decides three things independently: whether the protected route
body renders, whether a retained identity is shown, and which actions the
chrome offers.

| Status | Protected route body | Identity shown | Protected actions | Escape actions |
|--------|----------------------|----------------|-------------------|----------------|
| `authenticated` | rendered | yes | enabled | enabled |
| `mfa_pending` | withheld | yes | disabled | enabled |
| `checking` | withheld | no | disabled | disabled |
| `unavailable`, last snapshot reported a session | withheld | yes, last accepted | disabled | enabled |
| `unavailable`, otherwise | withheld | no | disabled | disabled |
| `anonymous` | redirected to sign-in | no | disabled | not applicable |

- **Escape actions** are sign-out and stop-impersonation. They follow
  `escapeActionsAvailable`, which is true whenever a retained identity is
  shown. A user whom the tab cannot verify must still be able to leave.
- **Protected actions** are every other control that issues a mutation from
  the chrome, such as plan-preview activation. They follow
  `protectedActionsAvailable`, which is true only for `authenticated`. While
  authority is uncertain the server may already have retired the session.
- **The retained identity is deliberate.** Showing the last accepted user
  during an outage tells them they were not signed out. It grants nothing;
  mutation controls are gated separately.
- **`mfa_pending` withholds the route body in place.** A refresh can move a
  mounted protected route from `authenticated` to `mfa_pending` without a
  navigation, so no route guard reruns. The root view withholds the body so
  account data does not stay on screen while stores reset. `/mfa-verify`
  does not require authentication and stays reachable.
- **An `unavailable` hydration schedules recovery.** When the hydration
  payload itself reports `unavailable`, `init()` starts the coordinator's
  backoff at its first step instead of waiting for the visibility and
  staleness check, which can be fifteen minutes away. After initialization,
  failed refreshes continue the same backoff.

#### Rejection disposition {#rejection-disposition}

When an API call is rejected, the coordinator
decides whether it owns the user-visible message and returns that decision as
a `RejectionDisposition`:

- owned by the coordinator: `reconciling` or `will-reload`;
- not owned: `skipped-carve-out`, `throttled`, or `nonauth`.

The axios interceptor attaches the disposition to the rejected error.
`useAsyncHandler` suppresses its own notice only when the disposition says the
coordinator owns the message. The carve-out list and the throttle decision
exist only in the coordinator; no consumer keeps a copy. With two copies, a
throttled reconciliation left the user with no feedback: the handler assumed
the coordinator would speak and the coordinator did not run.

#### Commit generation ownership {#commit-generation-ownership}

`commit()` captures its request generation before its first `await`. After
every `await` it checks that the generation is still current, and if it is not
it skips the rest: applying the snapshot, resetting the failure count,
scheduling the next refresh, and recording the check time. The newer run does
those.

Account-scoped stores are cleared before the snapshot is applied, not after.
The dynamic-import `await` in that clearing therefore happens while no new
snapshot is visible, and a superseded commit leaves nothing applied. To any
caller, a commit either completes or has no effect.

## Trade-offs

- **We lose:** A single scalar that appears to order every snapshot globally.
  Consumers must carry an epoch and version together, and authentication
  transitions have an explicit acceptance rule. The sidecar registry gains a
  second value model, the bare-integer counter, beside its envelopes. An
  ordinary refresh can force a page load in a tab without any action in that
  tab, and session expiry now ends in a page load instead of an in-place
  update.
- **We gain:** Deterministic ordering across workers for one browser session
  without exposing installation-wide snapshot volume. Ordering state uses the
  project's existing session lifetime and cleanup boundary, and anonymous
  sessions add no Redis keys or commands. No rule can keep a tab on a session
  that has ended, and one page-load path replaces every per-store teardown.
- **Risk:** Reseeding depends on the Redis clock moving forward across a key
  loss. A regression larger than the lost key's age, for example after
  failover to a replica with a skewed clock, can produce a lower version
  within a live epoch. The client then takes the anomaly path: one retry,
  then a forced page load. The seeded counter, TTL refresh, and anomaly
  recovery must therefore be tested together.
- **Risk:** A forced page load can discard unsubmitted input where the browser
  shows no `beforeunload` prompt: on mobile platforms, or in any view that has
  not adopted the shared guard. Secret drafts are deliberately not persisted
  to browser storage, so there is no recovery after the reload.
- **Risk:** `snapshot_epoch` is a stable per-session identifier while the
  application secret remains unchanged, and diagnostics record it. It is not a
  credential and cannot be reversed to the session ID, but it correlates one
  session's events and must be treated as such wherever diagnostics are stored.
- **Risk:** Rotating the application secret changes every epoch. Every open
  tab with an ordered session takes the session-replacement path at its next
  refresh. The refresh interval's jitter spreads those page loads, and
  operators should expect them.

## Consequences

Bootstrap consumers will distinguish complete snapshots from local patches.
Only complete snapshots participate in epoch, version, and request-generation
acceptance; local optimistic changes remain possible but cannot redefine
server order.

Web Core gains an allocation middleware between session load and the router.
`GET /bootstrap/me` gains a `Cache-Control: no-store` header. Views that hold
unsubmitted input adopt the shared `beforeunload` guard, starting with the
secret creation form. The client gains a stale-session state and notice for a
cancelled or repeated forced page load.

All refresh entry points, including periodic checks and refreshes following
authentication operations, will converge on one coordinator. Store updates
that currently occur outside the bootstrap-store update path will happen only
after the coordinator accepts the complete response.

Tests will cover:

- **Allocation:** epoch derivation, atomic version allocation, allocation
  ahead of the authentication strategy, no allocation and no Redis key for an
  anonymous session, seeding and reseeding after key loss, TTL refresh and
  purge, and refusal of the generic sidecar API for counter fields.
- **Payload:** schema validation of the epoch and version as a unit, large
  decimal versions, a missing or malformed generation timestamp applying with
  a diagnostic, a 503 from `GET /bootstrap/me` on allocation failure, and the
  `Cache-Control: no-store` header.
- **Acceptance:** hydration initialization, an unordered tab applying
  snapshots until the first ordered one, degraded hydration, strictly newer
  acceptance, each anomaly cause retrying once and then forcing a page load,
  authorized authentication epoch transitions, non-advancing local patches,
  overlapping request generations, and authentication invalidation.
- **Session end and replacement:** session expiry, server-side revocation, and
  logout in another tab forcing a page load whatever their ordering metadata,
  and a session replacement on an ordinary refresh forcing a page load without
  applying the snapshot.
- **Forced page load:** conditional registration and removal of the
  `beforeunload` guard, the stale-session state after a cancelled reload, and
  the reload-loop bound.
- **Rollout:** a tab with a watermark meeting a worker without the contract,
  and hydration from such a worker starting the tab unordered.
- **Diagnostics:** non-normative clock-regression diagnostics.

## Related

- [Frontend Architecture](../architecture/frontend.md) — current hydration,
  bootstrap-store, and `GET /bootstrap/me` data flow
- `lib/onetime/session/sidecar.rb` — session-scoped storage, lifetime, and
  cleanup boundary
- `src/schemas/contracts/bootstrap.ts` — shared Zod/Rhales bootstrap contract
- `src/shared/stores/bootstrapStore.ts` — client bootstrap state boundary
- `src/shared/stores/authStore.ts` — periodic and authentication-related
  refresh entry points, and the `logout()` teardown scope
- `apps/web/core/controllers/page.rb` — `bootstrap_me`, which sets no
  `Cache-Control` header today
- `src/apps/workspace/domains/DomainBrand.vue` — the existing `beforeunload`
  guard
- [MDN: `beforeunload` event](https://developer.mozilla.org/en-US/docs/Web/API/Window/beforeunload_event)
  — sticky activation, `preventDefault()`, conditional registration, mobile
  reliability
- [HTML Standard: unloading documents](https://html.spec.whatwg.org/multipage/browsing-the-web.html#unloading-documents)
  — the "prompt to unload" conditions
- [web.dev: Back/forward cache](https://web.dev/articles/bfcache) and
  [Chrome: Deprecating the unload event](https://developer.chrome.com/docs/web-platform/deprecating-unload)
  — add `beforeunload` listeners only while changes are unsaved

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
- **A counter that starts at 1:** Rejected because the key can be lost while
  the session lives: API requests extend the blob without refreshing the key,
  and Redis can evict it. The restarted counter would sit below the accepted
  version, so every benign key loss would end in a forced page load. The seed
  is not what delivers expiry and revocation to the tab; the session-ended
  rule is.
- **Subjecting a session end to version ordering:** Rejected because a rule
  that can reject `authenticated: false` can keep a tab presenting a session
  that no longer exists. The request succeeded, so the consecutive-failure
  limit would never fire. A stale response that ends a session costs a page
  load; a rejected one that should have ended it costs a security boundary.
- **Rejecting an unexpected epoch on an ordinary refresh:** Rejected for the
  same reason. Request generation already excludes stale responses, so a new
  epoch on the current generation is treated as a session replacement.
- **Applying an ended or replaced session in place:** Rejected because it
  depends on a complete teardown of session-scoped stores, which
  `authStore.logout()` does not provide. A forced page load discards all
  client state without an inventory of stores.
- **Ordering anonymous sessions:** Rejected because an anonymous tab never
  refreshes, so it has no stream to order. It would add a Redis key and a Lua
  call to every anonymous page view, which is most of the traffic.
- **Re-running identity resolution after allocation:** Rejected in favour of
  allocating ahead of the authentication strategy. Two resolutions in one
  request could disagree, and the snapshot would then report an identity
  other than the one that authorized the request.
- **Leaving a rejected snapshot without recovery:** Rejected. A retired epoch,
  or missing metadata from a worker that predates the contract, would
  otherwise be dropped on every refresh while the request counts as a
  success. Every anomaly shares one bounded path: one retry, then a page load.
- **A custom confirmation before a forced page load:** Rejected in favour of
  the browser's `beforeunload` prompt. The platform prompt also covers user
  reloads, tab close, and hard navigations, and its conditions are specified
  and documented. A custom dialog would cover only this path.
- **Allocating the version after the snapshot state is read:** Rejected
  because an end stamp guarantees only that a snapshot omits writes committed
  after its allocation, which says nothing about how stale it is. A start
  stamp guarantees that a snapshot reflects every write committed before its
  allocation. Neither placement orders overlapping requests. Request
  generation does, so no acceptance decision in one tab depends on the
  placement. The choice fixes what a version means to any consumer that
  compares two of them. The cost is that allocation must run ahead of the
  authentication strategy.
- **Gating acceptance on `snapshot_generated_at`:** Rejected because the field
  orders nothing. A guard that rejected a malformed timestamp would discard
  snapshots whose epoch and version are valid, including logouts and
  permission downgrades, over a formatting difference between serializers.
- **An epoch derived from the session ID and a random token created with the
  counter:** This would surface counter loss as an epoch change and remove
  the dependence on the Redis clock. Rejected because every benign key loss in
  a live session, such as eviction or a lapsed TTL, would then force a page
  load, where the seeded counter makes it invisible. The clock-regression case
  it removes already ends in the same forced page load.
- **`HINCRBY` on the session:** Rejected because `session:<sid>` is an encrypted
  Redis string rather than a hash, and each `SessionSidecar` field is already
  its own Redis string. A counter-specific sidecar `INCR` preserves the current
  key naming, lifetime, and cleanup model. It does not fit the envelope value
  model, which is why the registry gains a counter policy.

### Caller-contract alternatives considered and rejected (2026-09-22)

- **Re-sending the authentication POST when verification fails:** Rejected
  because the POST can consume a nonce, a rate-limit slot, or a lockout
  counter. Verification is the idempotent step, so it is the one retried.
- **Treating `superseded` as a failure in auth completion:** Rejected because
  a newer coordinator run has already reconciled. Surfacing an error, or
  navigating on the older result, would contradict the run that owns the
  destination.
- **Hiding the retained identity during an outage:** Rejected because it
  offered "Sign in" to a user who was still signed in. The defect was that
  mutation controls were not gated separately from identity.
- **Gating escape actions on `authenticated`:** Rejected because a user whom
  the tab cannot verify would have no way to sign out or stop impersonating.
- **Keeping the carve-out list in each consumer of a rejection:** Rejected
  because the copies drift, and a consumer cannot know whether the
  coordinator was throttled. The coordinator returns its decision instead.
- **A generation check inside each store's reset:** Rejected in favour of
  clearing stores before the snapshot is applied. Ordering makes the whole
  commit appear atomic; per-store checks would need every store to know about
  generations.
- **Parking the transition message only when the status is `reloading`:**
  Rejected because `reloading` means `reload()` was called, not that the
  navigation happened. A cancelled `beforeunload` prompt would still leave
  the park behind. The time limit covers every cause.

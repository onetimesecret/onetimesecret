# Customer-session failure matrix

What each surface answers for each state of a customer session, where the
surfaces diverge, and the wire contract that now carries the verdict across
the server boundary.

- Issues: #4452 (this matrix), #4462 (`auth_status` and failure codes), #4457
  (snapshot ordering fields). Epic #4451.
- Recorded: 2026-09-18, against commit `b7f32a0af`. File and line references
  below are at that commit.
- Status of this document: it is the prose twin of an executable matrix. When
  the two disagree, the specs are right and this file is stale.

## The executable matrix

| What | Where |
|---|---|
| Matrix rows (one per state) and the shared expectations | `spec/support/customer_session_failure_matrix.rb` (`CustomerSessionFailureMatrix::STATES`) |
| Full mode: every state × every surface (44 examples) | `spec/integration/full/customer_session_failure_matrix_spec.rb` |
| Simple mode: the states that exist without an auth database (24 examples) | `spec/integration/simple/customer_session_failure_matrix_spec.rb` |
| `/auth` (Rodauth) surface: refusal bodies and codes | `spec/integration/full/auth_customer_session_evaluator_spec.rb`, `apps/web/auth/spec/integration/full_mfa/customer_session_evaluator_mfa_pending_spec.rb` |
| Snapshot ordering through the whole request | `spec/integration/full/bootstrap_snapshot_ordering_spec.rb` |
| v0.27 scenarios (#4466 rotation and cookie selection, #4467 remember-me) | `spec/integration/full/customer_session_continuation_baseline_spec.rb` |

Run them:

```bash
tests/lanes/run full-sqlite --only spec/integration/full/customer_session_failure_matrix_spec.rb
tests/lanes/run simple --only spec/integration/simple/customer_session_failure_matrix_spec.rb
```

Each example records the HTTP status, the evaluator verdict memoized for the
request, the strategy's bracket marker, the wire fields, whether any customer
identity reached the response, what happened to the active-session row (with
the SQL captured), and the request ID. No example records a credential: the
fixtures never print a password, a session ID, a cookie or a CSRF token, and
the matrix asserts the session ID is absent from every public payload.

## Surfaces

| Surface | Request | Route auth | Decides through |
|---|---|---|---|
| Protected HTML | `GET /dashboard` (`Accept: text/html`) | `sessionauth` | `BaseSessionAuthStrategy` → `CustomerSessionEvaluator` |
| Hydrated HTML | `GET /` (`Accept: text/html`) | `noauth` | `NoAuthStrategy` → evaluator → `InitializeViewVars` → serializers |
| Bootstrap | `GET /bootstrap/me` | `noauth` | same as hydrated HTML |
| Protected API | `GET /api/account/` | `sessionauth,basicauth` | `BaseSessionAuthStrategy`, then `BasicAuthStrategy` |
| `/auth` (full mode only) | e.g. `GET /auth/account` | Roda + Rodauth | `apps/web/auth/router.rb` → evaluator → `Auth::SessionRecheck` |

Since #4453 every surface reads the same verdict
(`lib/onetime/session/customer_session_evaluator.rb`), memoized once per
request. The matrix exists to keep that true.

## Wire contract

### `auth_status` — public surfaces

Hydration always answers 200. `GET /bootstrap/me` normally answers 200, but
returns a retryable 503 (with `Retry-After: 5`) when an ordered session's
snapshot metadata cannot be allocated (ADR-046 step 7). Neither surface
carries a session-failure code. They state the session through `auth_status`
(`lib/onetime/session/auth_status.rb`):

| Evaluator status | `auth_status` | `authenticated` | `awaiting_mfa` | `cust` |
|---|---|---|---|---|
| `:authenticated` | `authenticated` | `true` | `false` | object |
| `:mfa_pending` | `mfa_pending` | `false` | `true` | `null` |
| `:anonymous` | `anonymous` | `false` | `false` | `null` |
| `:rejected` | `anonymous` | `false` | `false` | `null` |
| `:unavailable` | `unavailable` | `false` | `false` | `null` |
| none (error-recovery render), session names a customer | `unavailable` | `false` | `false` | `null` |
| none (error-recovery render), otherwise | `anonymous` | `false` | `false` | `null` |

`checking` is a client-only value and is never sent. `authenticated` and
`awaiting_mfa` are computed from `auth_status` in
`Core::Views::AuthenticationSerializer`, so they cannot disagree with it. An
`authenticated` claim that lacks either the verdict projection or its customer
degrades to `unavailable`, never to a serialized identity.
`had_valid_session` is still emitted and is deprecated (#4468).

### `code` and `code_scope` — refusals

A JSON 401 caused by the customer session carries two additive fields
(`lib/onetime/session/failure_code.rb`). The `code` is the evaluator reason
verbatim; there is no second vocabulary. Statuses, redirects, and the existing
`error`, `message`, `error_type`, `success` and `timestamp` fields are
unchanged.

| Evaluator reason = `code` | `code_scope` | Marker in `message` (session-only routes) | API | Protected HTML | `/auth` router |
|---|---|---|---|---|---|
| `session_missing` | `customer_session` | `[SESSION_MISSING]` | 401 | 302 `/signin` | continues as anonymous |
| `not_authenticated` | `customer_session` | `[SESSION_NOT_AUTHENTICATED]` | 401 | 302 | continues as anonymous (see Divergence 7) |
| `awaiting_mfa` | `customer_session` | `[SESSION_AWAITING_MFA]` | 401 | 302 | 401 `error: "Authentication required"` off the MFA routes; session kept |
| `identity_missing` | `customer_session` | `[IDENTITY_MISSING]` | 401 | 302 | session destroyed; 401 `web.auth.security.session_expired` |
| `surface_mismatch` | `customer_session` | `[SESSION_SURFACE_MISMATCH]` | 401 | 302 | destroyed; 401 `session_expired` |
| `customer_not_found` | `customer_session` | `[CUSTOMER_NOT_FOUND]` | 401 | 302 | destroyed; 401 `session_expired` |
| `account_suspended` | `customer_session` | `[ACCOUNT_SUSPENDED]` | 401 | 302 | destroyed; 401 `session_expired` |
| `stale_credentials` | `customer_session` | `[SESSION_STALE_CREDENTIALS]` | 401 | 302 | destroyed; 401 `session_expired` |
| `active_session_revoked` | `customer_session` | `[SESSION_REVOKED]` | 401 | 302 | destroyed; 401 `session_expired` |
| `active_session_unavailable` | `verification_unavailable` | `[SESSION_UNVERIFIED]` | 401 | 302 | 401 `error_type: "SessionUnverified"`; session kept |
| `customer_unavailable` | `verification_unavailable` | `[SESSION_UNVERIFIED]` | 401 | 302 | same as above |
| `admin_session_expired` | `admin_session` | `[ADMIN_SESSION_EXPIRED]` | 401 (`/api/colonel` only) | n/a | not reached: the router supplies no admin boundary to the evaluator |

`customer_unavailable` is also the answer when the request's surface cannot be
read. A datastore blip makes DomainStrategy classify a custom domain or a
platform subdomain `:invalid`. `Onetime::SessionSurface.match_status`
classifies that host again. If the lookup answers, the session is compared as
usual. If it fails again, the surface is unknown rather than wrong, so the
session is kept instead of being destroyed as `surface_mismatch`.

Scopes are what a client acts on:

- `customer_session`: the session was examined and is not authenticated.
  Reconcile against the server.
- `verification_unavailable`: the session could not be verified. Not a verdict
  and never a sign-out.
- `admin_session`: the admin-only timeout. The customer session is untouched.
- `credential` is reserved for login, reauthentication and API-key rejections
  (#4469) and is not emitted. A 401 without a `code` makes no statement about
  the customer session: that includes a rejected `Authorization` header, a
  failed login, the route-level `Authentication required` refusals inside
  `apps/web/auth/routes/*.rb` for a request Rodauth does not consider logged
  in, and any backend that predates this contract.

How the pair gets onto the response:

- Otto surfaces: Otto renders the 401 inside the gem from the failure string
  alone. `BaseSessionAuthStrategy#failure_for` stashes the typed reason in the
  Rack env and `Onetime::Middleware::SessionFailureCode` adds the pair to the
  body. It annotates only a JSON 401 produced by Otto's auth chain after a
  session strategy refused, and never when the request carried an
  `Authorization` header.
- `/auth`: `Auth::Router#session_refusal` merges the pair into the four
  refusal bodies, keyed by the reason the router acted on
  (`Auth::SessionRecheck`'s where it differs from the evaluator's).

The frontend's copy is `src/schemas/contracts/session-failure.ts`;
`spec/unit/onetime/session/failure_code_spec.rb` fails if the two tables
differ.

### Snapshot ordering fields (ADR-046)

`snapshot_epoch`, `snapshot_version` and `snapshot_generated_at` are present
on a public payload only when it reports a session (`auth_status`
`authenticated` or `mfa_pending`), and are omitted, never null, otherwise. The
"Ordered" column below records this per state. A session end therefore always
reaches the client as a plain unordered payload, whatever happened to the
counter. When a payload reports a session and the pair could not be allocated,
`GET /bootstrap/me` answers 503 with `Retry-After: 5`; hydration renders
without the pair.

## The matrix

`verdict` is the evaluator status. "Row" is the effect on the
`account_active_session_keys` row. Surfaces: PH protected HTML, HH hydrated
HTML, BM `GET /bootstrap/me`, PA protected API. For PA the wire `message` is
always `[AUTH_HEADER_MISSING] No authorization header` (Divergence 1); the
session marker is the one the session strategy failed with.

| State | Surface | verdict | Status | Wire answer | Session marker | Ordered | Row | Diverges |
|---|---|---|---|---|---|---|---|---|
| `missing_anonymous` | PH | anonymous | 302 | `Location: /signin` | `SESSION_NOT_AUTHENTICATED` | – | none | |
| | HH | anonymous | 200 | `auth_status: anonymous` | – | no | none | |
| | BM | anonymous | 200 | `auth_status: anonymous` | – | no | none | |
| | PA | anonymous | 401 | `code: not_authenticated` | `SESSION_NOT_AUTHENTICATED` | – | none | D1 |
| `revoked` | PH | rejected | 302 | `/signin` | `SESSION_REVOKED` | – | none (already gone) | |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | none | D4 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | none | D4 |
| | PA | rejected | 401 | `code: active_session_revoked` | `SESSION_REVOKED` | – | none | D1 |
| `inactive` | PH | rejected | 302 | `/signin` | `SESSION_REVOKED` | – | deleted | D2 |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | deleted | D2, D4 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | deleted | D2, D4 |
| | PA | rejected | 401 | `code: active_session_revoked` | `SESSION_REVOKED` | – | deleted | D1, D2 |
| `absolute_expired` | PH | rejected | 302 | `/signin` | `SESSION_REVOKED` | – | deleted | D2 |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | deleted | D2, D4 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | deleted | D2, D4 |
| | PA | rejected | 401 | `code: active_session_revoked` | `SESSION_REVOKED` | – | deleted | D1, D2 |
| `legacy_unstamped` | PH | authenticated | 200 | page | – | – | unchanged | D5 |
| | HH | authenticated | 200 | `auth_status: authenticated`, `cust` | – | yes | unchanged | D5 |
| | BM | authenticated | 200 | `auth_status: authenticated`, `cust` | – | yes | unchanged | D5 |
| | PA | authenticated | 200 | account JSON | – | – | unchanged | D5 |
| `mfa_pending` | PH | mfa_pending | 302 | `/signin` | `SESSION_AWAITING_MFA` | – | unchanged | |
| | HH | mfa_pending | 200 | `auth_status: mfa_pending`, no account fields | – | yes | unchanged | |
| | BM | mfa_pending | 200 | `auth_status: mfa_pending`, no account fields | – | yes | unchanged | |
| | PA | mfa_pending | 401 | `code: awaiting_mfa` | `SESSION_AWAITING_MFA` | – | unchanged | D1, D7 |
| `suspended` | PH | rejected | 302 | `/signin` | `ACCOUNT_SUSPENDED` | – | unchanged | D6 |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | PA | rejected | 401 | `code: account_suspended` | `ACCOUNT_SUSPENDED` | – | unchanged | D1, D6 |
| `credential_stale` | PH | rejected | 302 | `/signin` | `SESSION_STALE_CREDENTIALS` | – | unchanged | D6 |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | PA | rejected | 401 | `code: stale_credentials` | `SESSION_STALE_CREDENTIALS` | – | unchanged | D1, D6 |
| `tenant_surface_mismatch` | PH | rejected | 302 | `/signin` | `SESSION_SURFACE_MISMATCH` | – | unchanged | D6 |
| | HH | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | BM | rejected | 200 | `auth_status: anonymous` | – | no | unchanged | D4, D6 |
| | PA | rejected | 401 | `code: surface_mismatch` | `SESSION_SURFACE_MISMATCH` | – | unchanged | D1, D6 |
| `authentication_database_unavailable` | PH | unavailable | 302 | `/signin` | `SESSION_UNVERIFIED` | – | unchanged | D3 |
| | HH | unavailable | 200 | `auth_status: unavailable` | – | no | unchanged | |
| | BM | unavailable | 200 | `auth_status: unavailable` | – | no | unchanged | |
| | PA | unavailable | 401 | `code: active_session_unavailable`, scope `verification_unavailable` | `SESSION_UNVERIFIED` | – | unchanged | D1, D3 |
| `customer_storage_unavailable` | PH | unavailable | 302 | `/signin` | `SESSION_UNVERIFIED` | – | unchanged | D3 |
| | HH | unavailable | 200 | `auth_status: unavailable` | – | no | unchanged | |
| | BM | unavailable | 200 | `auth_status: unavailable` | – | no | unchanged | |
| | PA | unavailable | 401 | `code: customer_unavailable`, scope `verification_unavailable` | `SESSION_UNVERIFIED` | – | unchanged | D1, D3 |

In simple mode there is no auth database and no active-session row, so
`revoked`, `inactive`, `absolute_expired` and
`authentication_database_unavailable` do not exist; the remaining states answer
exactly as above.

On an **active** full-mode session whose row is older than
`ActiveSessionGate::TOUCH_INTERVAL` (300 s), every surface that evaluates the
session refreshes the row's `last_use`, with one exception:
`GET /bootstrap/me` verifies the session and refreshes nothing (D8). The
full-mode spec pins both halves: hydrated HTML leaves the row `:touched`, the
bootstrap poll leaves it `:unchanged` with no write issued.

A request that is **refused** refreshes nothing on any surface, in either
mode: not `last_use`, not the sidecar's `last_activity_at`, and not the Rack
session blob's TTL.

## Divergences

**D1. On the protected API the `message` never named the session failure.**
`/api/account/` is `auth=sessionauth,basicauth`. Otto renders the last failure
in the chain, which is `BasicAuthStrategy`'s, and for a browser that is always
`[AUTH_HEADER_MISSING] No authorization header`
(otto 2.10.0, `lib/otto/security/authentication/route_auth_wrapper.rb:256-271`). Every one of
the refusals above was therefore byte-identical on the wire before #4462
except for `timestamp`, and a revocation could not be told from an outage or
from a request that never had a session. The typed reason existed only in the
server log. `code`/`code_scope` is what now carries it; `message` is
unchanged. The session marker still appears in `message` on routes whose chain
is `sessionauth` alone.

**D2. A request that finds an expired row deletes it, on every surface.**
`inactive` and `absolute_expired` reach `ActiveSessionGate#expire`
(`lib/onetime/session/active_session_gate.rb:210-218`), which deletes the row
and answers `:revoked`. A `GET /bootstrap/me` poll is enough to do it. From
then on the state is indistinguishable from `revoked`, and both answer
`active_session_revoked`. The deadline that fired is named only in the server
log line.

**D3. An outage answers 401 (API) and 302 to `/signin` (HTML), not 5xx.** The
evaluator fails closed and the refusal is rendered as an authentication
failure. #4462 requires the existing HTTP behaviour to be preserved, so this
release keeps the statuses and adds `code_scope: verification_unavailable` so a
client can tell an outage from a rejection. See "Evidence" for the standards
position; moving these to 503 is left to #4469. The public surfaces already
distinguish the case (`auth_status: unavailable`).

**D4. Public surfaces report a rejected session as `anonymous`, with no
reason.** This is deliberate: bootstrap states identity, not diagnosis, and a
public, unauthenticated surface does not disclose why a session was refused.
The reason is in the server log under the same request ID, and on the API
`code` for a client that goes on to call a protected route.

**D5. `legacy_unstamped` authenticates without an active-session row.** A
full-mode Rack session with no `active_session_id_hmac` is exempt from the
gate, which answers `:skipped` (`active_session_gate.rb:156`,
`customer_session_evaluator.rb:20-24`). It cannot be revoked from the sessions
page. The exemption predates this work, is neither widened nor narrowed here,
and ages out with the sessions that carry it.

**D6. Public and protected Otto surfaces keep a definitively rejected session;
`/auth` destroys it.** `suspended`, `credential_stale`,
`tenant_surface_mismatch` and the other definitive rejections leave the Rack
session and its cookie in place on the four Otto surfaces, where it grants
nothing. The `/auth` router destroys the session before dispatch
(`apps/web/auth/router.rb`, the `:identity_missing … :admin_session_expired`
branch). The session is refused identically everywhere; only its cleanup
differs.

**D7. `/auth` authorizes from `account_id`, so it re-checks what the evaluator
had not reached.** Rodauth considers a session logged in when `account_id` is
present. MFA-pending and autologin sessions have that without the app-level
`authenticated` flag, and the evaluator answers them before its surface and
active-session checks. `Auth::SessionRecheck`
(`apps/web/auth/session_recheck.rb`) runs those two checks for them, so the
reason `/auth` acts on, and codes, can be `surface_mismatch` or
`active_session_revoked` where the other surfaces say `awaiting_mfa` or
`not_authenticated`.

**D8. The two public surfaces verify alike and differ in whether they count
as activity.** Until #4455 both refreshed `last_use` on an active row, so a
tab left open kept its session alive through its periodic poll. A page load
is a user action; a background poll is not. `GET /bootstrap/me` now declares
`activity=passive` in `apps/web/core/routes.txt`
(`Onetime::SessionActivity`). It runs the same SELECT, enforces both
deadlines and still removes an expired row (D2), but it moves none of the
three inactivity clocks: the active-session row's `last_use`
(`ActiveSessionGate`), the sidecar's `last_activity_at` that the admin idle
bound reads (`Operations::Sessions::TrackMetadata`), and the Rack session
blob's TTL, which is the only inactivity clock in simple mode
(`Onetime::Session#write_session`). Hydrated HTML is unchanged. This
divergence is deliberate and stays.

Two limits are worth knowing. The verdict is memoized per request, so a
refresh skipped for a passive reader is recorded in the env and performed by
the first activity reader served from the memo; over HTTP a request is one or
the other, so this is exercised in the unit specs. And a route declaration
covers the session check only: the dashboard's five-minute receipt refresh
and the secret-links status refresh are ordinary API requests on routes that
real navigation also uses, and no route option can tell the two apart.

**D8a. A client may declare a safe request passive.** The client knows which
of its requests a timer sent, so it says so with a request header:

```
X-Session-Activity: passive
```

`Onetime::SessionActivity.passive?` honours it next to the route option, and
the three clocks above treat the request exactly as they treat the poll. The
header can only take activity away:

| Rule | Why |
|---|---|
| Only the exact value `passive` is read (case and surrounding whitespace aside). | No value can make a passive route count as activity. |
| Honoured on `GET` and `HEAD` only, as an allowlist. | A request that changes state is something a person did; `POST`, `PUT`, `PATCH`, `DELETE` and any method not listed always count. |
| Read by the activity predicate and nothing else. | Authentication, the evaluator, both deadlines, revocation and every refusal code are identical with and without it (one matrix example per state pins this). |
| A passive request still creates the session's metadata record when none exists. | The record is what lists a session for its owner and for an operator; a session that only ever declared itself passive must not be able to stay off that list. |

What a caller gains by sending it is an earlier end to its own session, so the
server does not need to trust it and nothing is gained by forging it. One
cost is accepted: a passive request does not refresh the metadata record, so
the session list's last-activity time and country do not move for it. That is
the same for the route-declared poll. There is no CORS layer in this
application (the client is same-origin), so no allowed-headers list needs the
name; a deployment that adds a cross-origin gateway in front must allow
`X-Session-Activity` or the timers will count as activity again, which is the
safe direction.

Each poll that carries a session claim writes one `Bootstrap verification`
line (Session logger, info) with `passive`, the verdict, the queries and
writes issued against the active-session table, and the request id. A
passive poll of a live session reads `active_session_queries: 1,
active_session_writes: 0`. Pinned by
`spec/integration/full/passive_verification_spec.rb` and its simple-mode
twin.

## The reported incident

The report: an authenticated user was shown as signed out, or bounced to
sign-in, while the session was still valid on other requests.

What the evidence supports, and what it does not:
[ADR-045](../adr/adr-045-prioritizing-work.md) records that the captures "omit
the bootstrap body and subsequent API refusal reason" and that the evidence
"does **not** establish which strict-session check rejected the captured
request". The captures are not in the repository or in the issues. With D1 in
view, that gap was structural: on a `sessionauth,basicauth` route the wire
response could not have named the check even if the body had been captured.
**This document therefore does not name a single rejection path.** It names
the candidate set, each reproducible through a matrix state, and what would
discriminate between them.

Server-side candidates — a check that refuses a session the user believes is
valid:

| Candidate | Where | Matrix state | Why it fits |
|---|---|---|---|
| Inactivity or lifetime deadline fired on a poll | `active_session_gate.rb:171-172` → `expire` `:210-218` | `inactive`, `absolute_expired` | Deletes the row on whichever request arrives first, including a background poll; every later request is `revoked` (D2). Looks like a spontaneous sign-out. |
| Row absent | `active_session_gate.rb:170` → `revoked` `:225-228` | `revoked` | "Sign out everywhere", an operator, or Rodauth's sweep. |
| Auth database could not answer | `active_session_gate.rb:176-177` → `unavailable` `:252-256`; `customer_session_evaluator.rb:156-157` | `authentication_database_unavailable` | Transient; refuses with the same wire response as a rejection (D1, D3), and the session is valid again on the next request. Best fit for "valid on other requests". |
| Customer store could not answer | `customer_session_evaluator.rb:184-203` | `customer_storage_unavailable` | Same shape as above. |
| Request surface could not be read | `Onetime::SessionSurface.match_status` | `customer_storage_unavailable` | Same shape as above. Until #4450, a blip on a custom-domain or subdomain host destroyed the session as `tenant_surface_mismatch`, a real sign-out. |
| Tenant surface did not match | `customer_session_evaluator.rb:139` | `tenant_surface_mismatch` | A session established on one host presented on another refuses there and only there. |
| Credential watermark | `customer_session_evaluator.rb:148`, `:205-210` | `credential_stale` | A password change elsewhere invalidates this session. |

A seventh mechanism was found later, by the first real run of the #4459
browser tests, and runs the OTHER way (a signed-out user still shown as signed
in, then refused):

| Candidate | Where | Reproduced by | Why it fits |
|---|---|---|---|
| Logout undone by an in-flight request | `apps/web/core/controllers/authentication.rb` `#logout` cleared the Rack session only; the store is last-writer-wins (`lib/onetime/session.rb` `#write_session`) and every response re-sends the cookie | `spec/integration/full/logout_ends_active_session_spec.rb`; `e2e/auth/session-consistency.spec.ts` "a session ended outside the tab" | A request that loaded the session before `GET /logout` and committed after it wrote the whole blob back under the old id and re-installed the old cookie. The active-session row had never been removed, so the copy was a valid session: observed as `/api/organizations` 401, then `GET /bootstrap/me` `authenticated`, 30 ms after the logout. Tabs of one browser then disagree about whether the user is signed in. Fixed twice over. Logout removes the row first (`Onetime::ActiveSessionGate.end_session`), so in full mode a copy is refused as `active_session_revoked`. And every path that deletes a session blob first sets a 300-second ended-marker (`Onetime::SessionEnded`, key `ended_sid:<HMAC of the id>`), which `#write_session` looks for after its own `SET`: a late write is taken back out, reported as not saved, and sends no cookie. That covers what the row cannot: simple mode, which has no row, and a single-session revoke (`Operations::Sessions::RevokeForCustomer`, `DeleteSession`), which deletes the blob and leaves the row in both modes. `spec/integration/simple/logout_write_back_spec.rb` holds a real request open across the logout and across a revoke. |

Client-side amplifiers — code that turns one refusal, or one failed poll, into
a signed-out UI (unchanged since `56a95f8b6`; addressed by #4456, #4458,
#4459, #4460):

| Amplifier | Where | Effect |
|---|---|---|
| Applies `authenticated: false` in place | `src/shared/stores/authStore.ts:323-328` | Any poll that answers `authenticated: false` — including the transient outage rows, which answered exactly that before `auth_status` existed — flips the UI to signed-out with the session intact. |
| Client-only logout after three failed polls | `src/shared/stores/authStore.ts:349-350` | Three network or 5xx failures sign the user out locally; the server session is untouched. |
| Unconditional refresh on mount | `src/shared/components/layout/MastHead.vue:251-257` | A second `/bootstrap/me` on every page load, racing hydration, doubling exposure to the two rows above. |
| Session resurrection from `sessionStorage` | `src/shared/stores/authStore.ts:227-265` | `ots_auth_state` plus `had_valid_session` restores "authenticated" on an error page without a server statement. |

What would single one out: the refusal's request ID joined to the server log.
Every candidate logs a distinct line (`[active_session_gate] … inactivity
deadline`, `… no active-session row`, `… authdb unreachable`,
`[auth_strategy] Failed to load customer`,
`[SessionSurface] Could not re-classify an :invalid request`,
`:session_surface_mismatch`). From
this release the API response also carries `code`, so a browser capture alone
is enough.

Given "still valid on other requests", the transient rows
(`active_session_unavailable`, `customer_unavailable`) combined with the first
client amplifier are the most likely mechanism: before #4462 an outage poll
answered `authenticated: false` and the client applied it. That is an
inference from the matrix, not a finding from the captures.

## v0.27 scenarios

Recorded as a baseline so #4466 and #4467 start from observed behaviour, in
`spec/integration/full/customer_session_continuation_baseline_spec.rb`:

- **Rotation and cookie selection (#4466):** login rotates the anonymous
  session ID away and destroys the old blob; when a request carries duplicate
  `onetime.session` cookies the first one on the request is used.
- **Remember-me continuation (#4467):** after active-session revocation the
  remember credential is still live in the auth database but does not restore
  the session today.

## Security findings

The matrix was run looking for session fixation, authorization bypass and
credential disclosure. None was reproduced:

- No refused or unavailable state exposes `cust`, `custid`, `email` or the
  customer's external ID on any surface (asserted per cell).
- No public payload contains the session ID; `snapshot_epoch` is a keyed
  digest of it under a domain of its own and is not the colonel revoke handle
  (asserted).
- No compatibility path promotes a payload: the serializer derives both
  booleans from `auth_status`, and `effectiveAuthStatus()` in
  `src/schemas/contracts/bootstrap.ts` reads a payload without `auth_status`
  from the booleans, which can only withhold.
- Login rotates the session ID (baseline spec).

One finding came from the browser run rather than the matrix: `GET /logout`
could be undone by a request already in flight (see "The reported incident",
seventh mechanism). It is not fixation or bypass by a third party (the copy
is the user's own session, in their own browser), but a logout that does not
reliably end the session is a session-management defect (ASVS 7.4.1), and it
is fixed in both authentication modes in this release (`RISK-2026-09-19-01`).

Two observations that are not vulnerabilities are recorded as D1 (loss of the
refusal reason on the wire, fixed here) and in "Evidence" (no
`WWW-Authenticate` on the 401).

## Evidence

Per [ADR-048](../adr/adr-048-evidence-basis-for-security-decisions.md). Each
passage was read in the cited source on 2026-09-18.

**Session refusals answer 401.**
[RFC 9110 §15.5.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.5.2):
"The 401 (Unauthorized) status code indicates that the request has not been
applied because it lacks valid authentication credentials for the target
resource. The server generating a 401 response MUST send a WWW-Authenticate
header field (Section 11.6.1) containing at least one challenge applicable to
the target resource." A request whose session is missing, rejected or revoked
lacks valid credentials, so 401 is the matching status.
*Existing deviation, not introduced here:* the session 401 (rendered by Otto)
and the `/auth` 401s send no `WWW-Authenticate`. Cookie sessions have no
registered HTTP authentication scheme to challenge with. #4462 requires
existing HTTP behaviour to be preserved, so this is recorded and left for
#4469.

**An outage is not a credential failure; the status is kept and the scope says
so.** [RFC 9110 §15.6.4](https://www.rfc-editor.org/rfc/rfc9110.html#section-15.6.4):
"The 503 (Service Unavailable) status code indicates that the server is
currently unable to handle the request due to a temporary overload or
scheduled maintenance, which will likely be alleviated after some delay." By
that text 503 describes `active_session_unavailable` and
`customer_unavailable` better than 401 does. *OTS choice for v0.26.13:* keep
401 (D3) because #4462 forbids changing statuses in this release, and mark the
refusals `code_scope: verification_unavailable` so clients do not treat them
as a sign-out. This is a deliberate, recorded deviation with #4469 as its
remedy.

**`GET /bootstrap/me` answers 503 with `Retry-After` when ordering cannot be
allocated.** RFC 9110 §15.6.4, continuing: "The server MAY send a Retry-After
header field (Section 10.2.3) to suggest an appropriate amount of time for the
client to wait before retrying the request."
[§10.2.3](https://www.rfc-editor.org/rfc/rfc9110.html#section-10.2.3): "When
sent with a 503 (Service Unavailable) response, Retry-After indicates how long
the service is expected to be unavailable to the client." and "The Retry-After
field value can be either an HTTP-date or a number of seconds to delay after
receiving the response." *OTS choice:* 5 seconds, as delay-seconds.

**Bootstrap and personalized HTML are `private, no-store`, including the 503.**
[RFC 9111 §5.2.2.5](https://www.rfc-editor.org/rfc/rfc9111.html#section-5.2.2.5):
"The no-store response directive indicates that a cache MUST NOT store any
part of either the immediate request or the response and MUST NOT use the
response to satisfy any other request."
[§4.2.2](https://www.rfc-editor.org/rfc/rfc9111.html#section-4.2.2): "a cache
MAY assign a heuristic expiration time when an explicit time is not
specified". Without the header a bootstrap response may be reused, which is
one of the replay causes ADR-046 lists.
[OWASP ASVS 5.0.0 requirement 14.3.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x23-V14-Data-Protection.md):
"Verify that the application sets sufficient anti-caching HTTP response header
fields (i.e., Cache-Control: no-store) so that sensitive data is not cached in
browsers." *OTS choice (#4461):* the same value is the default for every
response the `/auth` app finishes (`plugin :default_headers` in
`apps/web/auth/router.rb`), since it answers nothing but authentication
state; a route that sets its own policy keeps it. JSON API responses under
`/api` default to `Cache-Control: private, no-store` through
`Onetime::Middleware::ApiCachePolicy` (RISK-2026-09-19-03); a route that
already set its own `Cache-Control` keeps it.

**An inactivity timeout has to measure inactivity.**
[OWASP ASVS 5.0.0 requirements 7.3.1 and 7.3.2](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v73-session-timeout):
"Verify that there is an inactivity timeout such that re-authentication is
enforced according to risk analysis and documented security decisions." and
"Verify that there is an absolute maximum session lifetime such that
re-authentication is enforced according to risk analysis and documented
security decisions." *OTS choice (#4455):* a timer-driven session check is
not user activity, so it verifies and moves no inactivity clock (D8); the
absolute lifetime is enforced by the same query and no request can move it.
The standard does not say which requests count as activity; treating the
poll as passive is this project's decision, recorded here. *OTS choice
(`RISK-2026-09-19-04`):* the same reasoning covers the client's other timers,
which the server cannot tell from navigation, so the client declares them
with `X-Session-Activity: passive` (D8a). The declaration is accepted
because it can only shorten the session of the caller that sends it: it is
ignored on every state-changing method and is no input to authentication.
Without it a tab left on the dashboard never reached the inactivity timeout
that 7.3.1 asks for.

**A terminated session must stop working everywhere, and ordering must not be
able to delay that.**
[OWASP ASVS 5.0.0 requirement 7.4.1](https://github.com/OWASP/ASVS/blob/v5.0.0/5.0/en/0x16-V7-Session-Management.md#v74-session-termination):
"Verify that when session termination is triggered (such as logout or
expiration), the application disallows any further use of the session. For
reference tokens or stateful sessions, this means invalidating the session
data at the application backend." The backend half is the evaluator and the
active-session gate. *OTS choice:* the ordering pair is attached only to a
payload that reports a session, and `GET /bootstrap/me` never answers 503 for
a payload that reports none, so an ordering failure cannot withhold a session
end from the client.

**The epoch is a truncated HMAC of the session ID.**
[RFC 2104 §5](https://www.rfc-editor.org/rfc/rfc2104.html#section-5): "We
recommend that the output length t be not less than half the length of the
hash output (to match the birthday attack bound) and not less than 80 bits".
HMAC-SHA256 truncated to 128 bits meets both bounds. *OTS choices:* the key is
the application secret; the domain string `bootstrap-snapshot-epoch:v1` is
separate from `SessionMetadata::HANDLE_DOMAIN` so the value published to the
tab is not the identifier the colonel revoke endpoint accepts.

**Judgment, no source determines it:** reporting a rejected session as
`anonymous` on public surfaces (D4) while giving the typed `code` on the
protected API. No standard read for this work addresses how much a refusal
should explain. The reasoning: the public surfaces answer any visitor and
should not describe account state; the API `code` is returned only to a
request that already presented the session cookie, names no account, and
distinguishes nothing an attacker could not already observe from the 401
itself. Codes such as `account_suspended` are reached only past the
`authenticated == true` check, that is, by the holder of a session that was
valid.

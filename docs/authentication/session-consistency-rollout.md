# Rolling out the v0.26.13 session-consistency package

Deployment notes and the staging review for the authentication package tracked
in [#4451](https://github.com/onetimesecret/onetimesecret/issues/4451) and gated
by [#4463](https://github.com/onetimesecret/onetimesecret/issues/4463). The wire
contract and per-surface behaviour are in
[customer-session-failure-matrix.md](./customer-session-failure-matrix.md); the
ordering rules are
[ADR-046](../adr/adr-046-bootstrap-state-ordering-contract.md).

## Deploy the backend and the frontend together

The package ships as one release. Do not cherry-pick a sub-issue into a
deployment, and do not serve a frontend bundle from this release against a
backend from before it (or the reverse) for longer than a rolling deploy takes.
Each half works against the other's previous version, but only in a degraded
form:

| Combination | What happens |
|---|---|
| New frontend, old backend | The payload has no `auth_status` and no ordering pair. The client derives the status from `authenticated` / `awaiting_mfa` (restrictive when they disagree) and runs unordered. Every signed-in page load makes one immediate `GET /bootstrap/me`. API `401`s carry no `code`, so a rejected call reconciles only while the tab holds a session. |
| Old frontend, new backend | The new fields are ignored. The old client still polls on startup and every 15 minutes; those polls no longer keep a session alive. It still signs the user out after three failed refreshes, and a `503` from `GET /bootstrap/me` counts as one. A protected API call refused during a verification outage answers `503` (below); the old client reports only `401`s to its coordinator, so it shows that call's error and reconciles nothing. It is not signed out by it. |
| Mixed workers during a rolling deploy | A tab that holds a watermark and reaches a worker without the contract gets a session snapshot with no pair. That is an anomaly: one immediate retry, and a second one on that retry reloads the tab. Each refresh gets its own retry; an anomaly whose retry failed does not count against a later one. The reload is bounded to once per minute per tab. |

Keep the mixed-worker window short. A blue/green switch avoids it entirely.

## The unversioned-payload rule

The server never labels a payload as ordered unless it allocated a version for
it.

- `snapshot_epoch` and `snapshot_version` appear together or not at all. They
  are omitted, never `null`, when the payload reports no session or when
  allocation failed.
- `GET /bootstrap/me` answers `503` with `Retry-After: 5` when the payload
  reports a session but no version could be allocated (datastore trouble). The
  client keeps its last accepted state and retries. A session that has ended is
  still reported as `200` with `auth_status: "anonymous"` while allocation is
  failing.
- A page load whose allocation failed still renders. Its payload omits the pair,
  the server logs `Bootstrap snapshot serialized without ordering`, and the tab
  makes one immediate refresh.
- A payload from a server without the contract (before this release, or after a
  rollback) is unordered. The client applies it as it did before this release.

Rolling back is therefore safe: signed-in tabs that hold a watermark reload once
and continue unordered.

## Operator-visible changes

- **Application secret rotation.** `snapshot_epoch` is an HMAC of the session id
  under the application secret. Rotating the secret changes every epoch, so each
  open signed-in tab reloads once at its next refresh. Sessions are not ended by
  this.
- **Idle sessions now expire.** `GET /bootstrap/me` is verified in full but does
  not count as activity. A signed-in tab left untouched reaches the inactivity
  deadline; before this release its own 15-minute poll kept it alive
  indefinitely. Expect more sessions ending by inactivity than before. The
  dashboard's receipt lists refresh every 5 minutes while their tab is visible
  and when it becomes visible again; those requests declare themselves with the
  request header `X-Session-Activity: passive` and do not count either, so a
  tab left on the dashboard signs out on schedule too. A hidden tab sends none.
  The header is honoured on `GET` and `HEAD` only and can only shorten the
  sender's own session. A proxy that strips unknown request headers turns
  those refreshes back into activity; it breaks nothing else.
- **Log fields.** Session store lines carry `session_handle` instead of
  `session_id`, and `redis_key` is gone. So do the sign-in, sign-out and
  password-reset lines, every `/auth` event line, and the request lines of
  `LOG_HTTP_CAPTURE=debug`: no log line writes a session id. Update any log
  query, alert or dashboard keyed on `session_id`.
- **Traffic.** A normal page load makes no `GET /bootstrap/me` request. Expect
  that endpoint's request rate, and the `Bootstrap verification` line count, to
  drop.
- **Caching.** `/auth` responses, and every `/api` response that sets no
  policy of its own, send `Cache-Control: private, no-store`. Confirm no
  intermediary overrides it.
- **A verification outage answers `503`.** A protected API or `/auth` request
  whose session could not be verified (datastore or auth database
  unreachable) answers `503` with `Retry-After: 5` and the body it answered
  `401` with before, including `code_scope: verification_unavailable`
  ([#4469](https://github.com/onetimesecret/onetimesecret/issues/4469)). The
  session is kept, as before. Update any alert that counted these as `401`s.
  The browser client's own handlers that key a sign-in message off a `401`
  (connected identities, the email-config poll, the SSO link confirmation)
  now show their generic or transient error for an outage instead, which is
  the right reading; the email-config poll's retry is bounded to 10 attempts.
  The client reads the body, so an intermediary configured to replace an
  origin `503` with its own error page turns the outage into an uncoded
  failure on the client: no sign-out, but no reconciliation either. Confirm
  origin `503` bodies pass through on the API hostnames.
- **Refusals carry `WWW-Authenticate`.** Every coded `401` from the API and
  `/auth` carries a challenge: `Session realm="onetimesecret"` for a session
  or form credential, `Basic realm="onetimesecret"` for a rejected
  `Authorization` header. Browsers act on neither for the browser client,
  which never sends `Authorization`.
- **Ended sessions leave a marker.** Logout and revocation write
  `ended_sid:<digest>` to the datastore with a 5-minute TTL. It holds no
  session id. A `Session write refused: the session was ended during this
  request` line (Session logger, info) means a request outlived its session
  and was stopped from restoring it; occasional lines are the mechanism
  working.
- **Session ids the server does not know.** A cookie naming an id with no
  stored session (expired, ended, or never issued) is given a new id on that
  request. Signing out removes the session's `session_metadata:<id>` key at
  once.
- **SQLite auth database.** Connections now open transactions with `BEGIN
  IMMEDIATE` and wait for locks with the GVL released. Concurrent sign-ups
  queue instead of answering `500`. The migration connections, including
  `rake auth:migrate`, do the same, so several processes booting at once no
  longer race on the file. No action needed; PostgreSQL locking is unchanged.
- **`/auth` can answer `503`.** When the auth database is saturated (a SQLite
  write lock held past the 5-second wait, or no free pooled connection on
  either engine) `/auth` answers `503` with `Retry-After: 1` and `error_type:
  AuthDatabaseBusy`, where it answered a generic `500`. Seeing it means more
  concurrent auth writes than the deployment has capacity for. It is logged
  at `warn` as `Auth router translated exception` with `error_type` and
  `status`; `Auth router unhandled exception` (`error`) now means only an
  exception `/auth` has no answer for.
- **Sign-up answers.** In full mode a sign-up for an existing account answers
  `400` with `{"error": "Unable to create account"}` whether that account is
  verified, unverified, or was created by a concurrent request a moment
  earlier. It used to answer `403` for an unverified account and `422` for a
  lost race. An ordinary duplicate logs `registration_blocked_existing_account`
  at info; `registration_blocked_auth_db_conflict` (error) now fires only when
  the auth database has the account and the datastore has no customer for it.

## Developer notes

- **Local hydration schemas.** The bootstrap payload gained `snapshot_epoch`,
  `snapshot_version` and `snapshot_generated_at`. In development the backend
  validates every page's hydration data against `public/schemas/*.json`
  (`Rhales::Middleware::SchemaValidator`, mounted only when
  `public/schemas/index.json` exists, failing loudly). Those files are generated
  and gitignored, and the schemas are closed, so a checkout that generated them
  before this release answers `500` for every page once it runs this code.
  `pnpm run dev` now repairs that: its `predev` step runs
  `pnpm run schemas:rhales:refresh`, which regenerates the schemas when the
  checkout has them and does nothing when it does not. If you start only the
  backend, or a page was requested before the frontend finished starting (the
  backend keeps the first schema it reads), run
  `pnpm run schemas:rhales:generate` and restart the backend. Deleting
  `public/schemas/*.json` turns the validation off.
- `pnpm run schemas:rhales:generate` had stopped producing anything ("No schema
  sections found"): the rake task did not know where `bootstrap.ts` lives. It
  now carries the same schema settings as the app. `error.rue` used a Mustache
  section Rhales cannot parse, so its schema was skipped with a warning.
  Nothing has rendered that template since error pages moved to the Vue entry
  point (October 2025), so it is removed with its view class; both remaining
  schemas (`index`, `admin`) generate, and a spec parses every Web Core
  template.

## Staging review

The review is a human step. #4463 stays open until someone has looked at each
signal below on staging and recorded the result on the issue. An unexpected
revocation, or more activity writes than before, reopens the assumption behind
it before a wider rollout.

| Signal | Where to look | Expected | Reopens |
|---|---|---|---|
| Refusal codes | Auth logger, message `Session refused`: `code`, `code_scope`, `request_id`, `route` | `session_missing`, `not_authenticated` and `awaiting_mfa` at debug. Others at info, and rare. `active_session_revoked` is expected after logout, explicit revocation, inactivity expiry, or the absolute-lifetime deadline (the same code covers all four). | #4453, #4455 |
| Verification-unavailable rate | The same line at warn with `code_scope: verification_unavailable`; API and `/auth` responses `503` with `code_scope: verification_unavailable` (a `401` with that scope is a backend from before v0.26.14); client view `verification-unavailable` | Zero outside a datastore or authdb incident. Users are not signed out during one. | #4460 |
| Redirect loops | Browser: sign in, sign out in a second tab, let a tab go stale. Client breadcrumb `forced-page-load` in category `bootstrap.ordering` | One reload per transition, one message, then `/signin`. Never two reloads within a minute. | #4465 |
| Ordering diagnostics | Client breadcrumbs in `bootstrap.ordering`: `anomaly`, `session-ended`, `session-replaced`, `degraded-hydration`, `allocation-failure`. Server: `Snapshot ordering allocation failed`, `Bootstrap snapshot serialized without ordering` | `anomaly` only during the rolling deploy. `session-ended` and `session-replaced` match real sign-outs and sign-ins. The two server lines absent. | #4457, #4464 |
| Clock regression | Client breadcrumbs `clock-regression`, `generated-at-missing`, `generated-at-malformed` | Diagnostics only; none of them rejects a snapshot. Frequent `clock-regression` means worker clocks disagree. | #4457 |
| Bootstrap query and write behaviour | Session logger, message `Bootstrap verification`: `passive`, `verdict`, `active_session_queries`, `active_session_writes`, `request_id` | `passive: true`, `active_session_queries: 1`, `active_session_writes: 0` in steady state. A non-zero write count on a poll is a defect. | #4455 |
| Startup requests | Browser network panel on a normal page load, signed in and signed out | Zero `GET /bootstrap/me` requests. | #4456 |
| MFA sign-in | Sign in to an account with TOTP enrolled | Lands on the challenge, completes, and the tab shows the account without a reload loop. | #4458, #4459 |

Join a client report to the server's decision by request id. Every response
carries it in the `x-request-id` header, and the `Session refused` and
`Bootstrap verification` lines log the same value. None of them carries a
session identifier.

## Known limits in this release

This section tracks the state as of v0.26.14, which adds the `WWW-Authenticate`
challenge and the outage `503` from
[#4469](https://github.com/onetimesecret/onetimesecret/issues/4469) to the
v0.26.13 package; in v0.26.13 itself those two were the first limits listed
here.

- Protected HTML still answers a verification outage with a `302` to
  `/signin`, where the API answers `503`. A navigation has no client to read
  a code; the session is kept (D3 in the failure matrix).
- Completing the second factor now renews the session id as the password
  step does (`after_two_factor_authentication` calls
  `Onetime::SessionRotation`; `RISK-2026-09-19-02`). The other establishment
  paths [#4466](https://github.com/onetimesecret/onetimesecret/issues/4466)
  lists (account switching, impersonation, SSO callbacks, autologin after
  signup and verification) are not yet proven to rotate, and the register row
  stays open for them. The unreleased state of each path is in the next
  section.

## Session-id renewal by path (unreleased)

These changes are not in v0.26.15 or earlier. They are tracked in
[#4466](https://github.com/onetimesecret/onetimesecret/issues/4466) and in the
register rows `RISK-2026-08-14-COOKIE-TOSSING` and `RISK-2026-09-19-02`.

Two paths change behaviour:

- **Simple-mode password sign-in** now clears the session and starts a new id,
  for verified and pending accounts alike
  (`AuthenticateSession#start_new_session!`,
  `apps/web/core/logic/authentication/authenticate_session.rb`). Nothing from
  the earlier session is carried. Before this change the verified path cleared
  the session and called `sess.replace!`, which no Rack session class defines,
  so the id was kept; the pending path did not clear the session at all. If
  the old id cannot be ended, the sign-in is refused: `503` for a JSON client,
  a redirect to `/signin` with a message otherwise. This path was not in the
  #4466 list above. Spec: `spec/integration/simple/login_session_rotation_spec.rb`.
- **Colonel step-up** (`POST /api/colonel/elevation`) now writes the window
  under a new id and carries the session data across, so the operator stays
  signed in (`apps/api/colonel/logic/colonel/elevate_session.rb`). If the old
  id cannot be ended, no window is granted and the request answers `403`
  `elevation_failed`. Specs:
  `spec/integration/full/colonel_elevation_session_rotation_spec.rb`,
  `spec/integration/simple/colonel_elevation_session_rotation_spec.rb`.

The full list, with the rule it follows, is in
`lib/onetime/session/rotation.rb` ("Which transitions renew the id"). The rule:
renew the id when the session gains capability, not when capability stays the
same or shrinks, or when whoever holds the id could already make the
transition at will. "Spec" means a spec that asserts the new id; "None" means
the path renews the id by its mechanism but no spec asserts it.

| Path | New id | Mechanism | Spec |
|---|---|---|---|
| Password sign-in, full mode | Yes | Rodauth `login_session`, which calls `clear_session`; this app defines that as `session.destroy` (`apps/web/auth/config/base.rb`) | `spec/integration/full/customer_session_continuation_baseline_spec.rb:18` |
| Password sign-in, simple mode | Yes (changed) | Session cleared, then `Onetime::SessionRotation.rotate!` | `spec/integration/simple/login_session_rotation_spec.rb:117` |
| OIDC callback sign-in, first sign-in and returning identity | Yes | `login_session` (rodauth-omniauth `login("omniauth")`) | `apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb:124`, `:134` |
| Platform SAML callback sign-in | Yes | `login_session` | `apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb:705` |
| Verify-account autologin | Yes | `login_session` (Rodauth `autologin_session`) | `apps/web/auth/spec/integration/full/verify_account_autologin_session_rotation_spec.rb:123` |
| Invite signup autologin | Yes | `rack.session.options[:renew]` | `spec/integration/full/active_sessions_spec.rb:624` |
| Second factor completed | Yes | `rotate!` (`apps/web/auth/config/hooks/two_factor.rb`) | `apps/web/auth/spec/integration/full_mfa/mfa_session_rotation_spec.rb:81` |
| Password change, full mode | Yes | `:renew` (`after_change_password`) | `spec/integration/full/hooks/account_lifecycle_spec.rb:487` |
| Colonel step-up | Yes (changed) | `rotate!`; no window when it does not complete | `spec/integration/full/colonel_elevation_session_rotation_spec.rb:69`, `spec/integration/simple/colonel_elevation_session_rotation_spec.rb:67` |
| Magic-link and passkey sign-in | Yes | Rodauth `login`, then `login_session` | None |
| SSO link-confirm sign-in | Yes | `rodauth.login('sso_link_confirm')` (`apps/web/auth/routes/sso_link_confirm.rb:233`) | None |
| Link-SSO password sign-in | Yes | `rodauth.login('password')` (`apps/web/auth/routes/link_sso.rb:322`) | None |
| SSO Connect callback (binds an identity to the signed-in account) | Yes | The callback ends in rodauth-omniauth's `login("omniauth")`, then `login_session` | None |
| Password change, simple mode | Yes | `:renew` (`AccountAPI::Logic::Account::UpdatePassword`) | None |
| Impersonation start and stop | No, by the rule | Starting needs no step-up, the overlay is read-only, and stopping returns the colonel's own capability (`apps/web/auth/operations/customers/impersonate.rb`, `stop_impersonation.rb`) | Not applicable |
| Organization switch (taken here to be what #4466 calls account switching) | No, by the rule | Changes the active organization, not the identity (`RequestHelpers#switch_organization`) | Not applicable |
| Re-authentication proof (`POST /auth/reauth`) | No (open) | `Onetime::RecentReauth.record` (`apps/web/auth/operations/reauthenticate.rb:324`) writes a single-use proof under the current id; the proof admits one SSO Connect initiation | Not applicable |
| TOTP and passkey setup | No (open) | Rodauth's `two_factor_update_session` adds the factor to the session without a new id; `apps/web/auth/config/hooks/mfa.rb` and `webauthn.rb` add none | Not applicable |

The last two rows raise what the session can do without a new id. They are
recorded as open in `RISK-2026-09-19-02`; their severity has not been
assessed.

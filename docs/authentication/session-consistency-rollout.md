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
| Old frontend, new backend | The new fields are ignored. The old client still polls on startup and every 15 minutes; those polls no longer keep a session alive. It still signs the user out after three failed refreshes, and a `503` from `GET /bootstrap/me` counts as one. |
| Mixed workers during a rolling deploy | A tab that holds a watermark and reaches a worker without the contract gets a session snapshot with no pair. That is an anomaly: one immediate retry, and a second consecutive one reloads the tab. The reload is bounded to once per minute per tab. |

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
  dashboard's two 5-minute data refreshes declare themselves with the request
  header `X-Session-Activity: passive` and do not count either, so a tab left
  on the dashboard signs out on schedule too. The header is honoured on `GET`
  and `HEAD` only and can only shorten the sender's own session. A proxy that
  strips unknown request headers turns those refreshes back into activity; it
  breaks nothing else.
- **Log fields.** Session store lines carry `session_handle` instead of
  `session_id`, and `redis_key` is gone. Update any log query, alert or
  dashboard keyed on `session_id` for those lines.
- **Traffic.** A normal page load makes no `GET /bootstrap/me` request. Expect
  that endpoint's request rate, and the `Bootstrap verification` line count, to
  drop.
- **Caching.** `/auth` responses send `Cache-Control: private, no-store` by
  default. Confirm no intermediary overrides it.

## Staging review

The review is a human step. #4463 stays open until someone has looked at each
signal below on staging and recorded the result on the issue. An unexpected
revocation, or more activity writes than before, reopens the assumption behind
it before a wider rollout.

| Signal | Where to look | Expected | Reopens |
|---|---|---|---|
| Refusal codes | Auth logger, message `Session refused`: `code`, `code_scope`, `request_id`, `route` | `session_missing`, `not_authenticated` and `awaiting_mfa` at debug. Others at info, and rare. `active_session_revoked` is expected after logout, explicit revocation, inactivity expiry, or the absolute-lifetime deadline (the same code covers all four). | #4453, #4455 |
| Verification-unavailable rate | The same line at warn with `code_scope: verification_unavailable`; client view `verification-unavailable` | Zero outside a datastore or authdb incident. Users are not signed out during one. | #4460 |
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

- Session `401`s send no `WWW-Authenticate` header, and verification outages
  answer `401` rather than `503`. Both are recorded in the failure matrix and
  belong to [#4469](https://github.com/onetimesecret/onetimesecret/issues/4469).

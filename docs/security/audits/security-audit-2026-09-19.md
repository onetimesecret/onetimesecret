# Security & Code Audit — 2026-09-19

- **Repo:** onetimesecret/onetimesecret
- **Baseline:** branch `feature/4451-auth-session-consistency` at `295038d24` (based on `main` @ `56a95f8b6`)
- **Method:** Targeted review of the v0.26.13 authentication session-consistency package (epic #4451, release gate #4463) and of `RISK-2026-08-13-02` against it. Current source was read for every item below. `tests/lanes/run full-mfa` passed: 17 examples, 0 failures.
- **Scope limit:** This is a disposition review of one package, not a fresh broad source or dependency audit. It re-rates nothing except the item it closes.

> **Historical record.** This report records the 2026-09-19 review. The [active security risk register](../active-risk-register.md) is the canonical status of every actionable finding.

---

## Bottom line

`RISK-2026-08-13-02` (MFA-incomplete sessions reaching account JSON and session-management routes) is resolved. The `/auth` router now refuses a first-factor-only session on every route except the ones that finish or abandon the challenge.

The package closes two further weaknesses it found itself: the raw session id in session-store and sign-in/sign-out log lines, and a `GET /logout` that an in-flight request could undo in full authentication mode.

Four Low residuals are filed. None is introduced by the package; three were found while testing it and one is the part of an idle-timeout fix that the package leaves open.

---

## Resolved since the cited audits

### 1. RESOLVED — MFA-incomplete sessions no longer reach account and session routes

**Source:** 2026-08-13 finding 2 (Low); carried as open in the 2026-09-09 audit.

**Fix:** `a99a07fb27` (`Gate Rodauth-logged-in /auth sessions that lack the app authenticated flag`), merged to `main` in #4483.

The finding recommended one shared gate rather than seven inline checks. That is what was built, as an allowlist. `apps/web/auth/router.rb` evaluates the shared customer-session verdict before it dispatches anything. For an `awaiting_mfa` verdict, `mfa_pending_route?` admits only:

- the Rodauth routes that complete the second factor (`MFA_PENDING_RODAUTH_ROUTES`),
- logout,
- `GET /mfa-status` (`MFA_PENDING_CUSTOM_ROUTES`), which the 2026-08-13 audit said must stay reachable.

Every other request is answered `401` with `code: awaiting_mfa` before `r.rodauth` or any hand-written route runs. The routes themselves still test `rodauth.logged_in?`; that is no longer the control. A route added later is refused by default, which removes the drift the finding warned about. The anonymous credential and recovery routes are refused as well, so a half-finished challenge cannot start an unrelated account flow.

The re-authentication routes added by #4419 (`GET /auth/reauth-offer`, `POST /auth/reauth`) use the same `rodauth.logged_in?` test and sit behind the same gate. #4421 (related-origins ownership) does not touch this surface.

**Verification:** the 2026-09-09 audit asked for regression coverage in which a first-factor-only session is rejected by every account and session route except `mfa-status`. `apps/web/auth/spec/integration/full_mfa/customer_session_evaluator_mfa_pending_spec.rb` now enumerates them (`295038d24`): six reads, both session-removal routes, identity removal and the re-authentication pair are refused with no account id or email in the body and no active-session row removed, while `mfa-status` answers `200`. The same spec covers a challenge session revoked mid-flow and one replayed on another surface.

**Residual considered and not filed:** an autologin session (account verification, invitation acceptance) is logged in to Rodauth without the `awaiting_mfa` flag and is not held to the allowlist. Both flows create the account in the same request, so no second factor exists to skip.

### 2. RESOLVED IN THIS PACKAGE — raw session id in log lines

`lib/onetime/session.rb` logged the raw session id throughout, including on info, warn and error lines and inside a logged Redis key. The Web Core authentication controller did the same on sign-in and sign-out. A logged session id can be replayed as the cookie. All of these now log `session_handle` (`Onetime::SessionMetadata.handle_for`), a keyed digest that cannot be turned back into the id (`52d5dae33`, `2e1f42c29`, `c07d351eb`).

This narrows `RISK-2026-08-14-L09` but does not close it: the HTTP request logger still records `session_id` when `LOG_HTTP_CAPTURE=debug` (`lib/onetime/application/request_logger.rb`), and raw emails remain at other sites.

### 3. RESOLVED IN THIS PACKAGE — `GET /logout` undone by an in-flight request (full mode)

The session store is last-writer-wins and every response re-sends the session cookie. A request that loaded the session before `GET /logout` and committed after it wrote the whole blob back and handed the browser its old cookie. The active-session row had not been removed, so that copy was a valid session. `c07d351eb` removes the row before the session is cleared, in both logout paths; the copy is then refused as `active_session_revoked`. `spec/integration/full/logout_ends_active_session_spec.rb` reproduces it.

---

## New findings

### 1. LOW — Simple mode: logout can be undone by an in-flight request

**Register:** `RISK-2026-09-19-01`

Simple authentication mode has no active-session row, so the fix above has nothing to remove there. A request in flight during the logout can still write the authenticated blob back and re-install the cookie in the same browser. The consequence is a user who signed out and is still signed in on that browser, which matters on a shared computer. It needs the user's own browser to have a request in flight at that moment; it gives a remote attacker nothing. OWASP ASVS 5.0.0 requirement 7.4.1 asks that logout make the session unusable.

**Required action:** record a short-lived per-session "ended" marker at logout and have `Onetime::Session#write_session` refuse to write a session that carries it, or renew the session id when the session is cleared.

### 2. LOW — Completing the second factor does not renew the session id

**Register:** `RISK-2026-09-19-02`

Rodauth renews the session id at the password step and not when the second factor completes; the application adds no renewal in `after_two_factor_authentication`. Observed in the browser lane: `snapshot_epoch`, which is derived from the session id, is unchanged across MFA completion. OWASP's session-management guidance asks for a new id on any privilege change. This is not exploitable as fixation here, because the id is already renewed at the password step and an MFA-pending session is refused everywhere but the challenge; it is defence in depth.

**Required action:** renew the session id when the second factor completes, and carry the active-session row and the sidecar across the renewal.

### 3. LOW — `/api` JSON responses send no `Cache-Control`

**Register:** `RISK-2026-09-19-03`

The package sets `private, no-store` on Web Core HTML, `GET /bootstrap/me` and `/auth`. JSON responses under `/api` were outside its scope. A personalized `GET /api/account/` `200` was observed with no `Cache-Control`, and outside the colonel audit export and a v1 helper the API applications set none in source. Without validators a browser is unlikely to reuse them, but OWASP ASVS 5.0.0 requirement 14.3.2 asks for an explicit anti-caching header on sensitive responses, and a shared intermediary is not bound by browser heuristics.

**Required action:** default authenticated `/api` responses to `Cache-Control: private, no-store`.

### 4. LOW — Dashboard data refreshes still count as session activity

**Register:** `RISK-2026-09-19-04`

The package stops `GET /bootstrap/me` polling from extending a session. Two 5-minute timers remain (`src/apps/workspace/dashboard/DashboardRecent.vue`, `src/apps/secret/components/SecretLinksTable.vue`). They call ordinary API routes that user navigation also calls, so the route-level `activity=passive` declaration cannot mark them. A tab left open on the dashboard therefore never reaches the inactivity deadline. Full mode's absolute session lifetime still applies.

**Required action:** let the client declare a timer-driven request passive (for example a request header read by `Onetime::SessionActivity.passive?`). A caller can only shorten its own session that way. It is a new wire contract and wants an ADR note.

---

## Observations — not filed as findings

- **Standards deviations kept on purpose.** Session `401`s send no `WWW-Authenticate` header (RFC 9110 §15.5.2), and verification outages answer `401` rather than `503`. #4462 required existing HTTP behaviour to be preserved; both are recorded in `docs/authentication/customer-session-failure-matrix.md` and belong to #4469. Neither discloses anything or weakens a control: an outage fails closed.
- **`snapshot_epoch` is visible to page JavaScript.** It is 128 bits of HMAC-SHA256 over the session id under the application secret, with a domain string distinct from the session handle's. It is not a credential and cannot be reversed to the id.
- **The `unavailable` client state keeps the last accepted snapshot** and lets protected navigation proceed while the protected view is withheld. This is display state; every protected API call is still authorized by the server.

---

## Current disposition

`RISK-2026-08-13-02` moves to the [resolution log](../records/resolution-log.md). The four new findings are entered in the [active security risk register](../active-risk-register.md). `RISK-2026-08-14-L09` stays open at its rating with its remaining sinks named.

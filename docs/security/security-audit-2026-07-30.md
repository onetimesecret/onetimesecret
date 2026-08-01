# Security & Code Audit — 2026-07-30

- **Repo:** onetimesecret/onetimesecret
- **Method:** Automated single-agent audit, delta-focused against the 2026-07-19 audit. Reviewed the 433 commits landed since then (session rotation #3810, SSO mailbox-proof linking #3840, invite-signup enumeration fix #3856, reset-password rate limiting #3872, billing sync work) with focus on auth/session/SSO/MFA, billing/Stripe, PostgreSQL/SQLite/Redis/RabbitMQ interactions, hardcoded secrets, weak crypto, and unsafe deserialization. Every finding below was verified by reading current source, not inferred from commit messages.

> **Historical reference.** This report reflects the codebase as of 2026-07-30 (audit start), when both findings below were open. **Update:** both findings have since been fixed — #1 same-day by PR #3949 (commit `2793e644`, "revoke sessions on password change/reset in simple mode"), merged before this report's own PR landed, and #2 by the follow-up that wired `ResetRequestRateLimiter` into the simple-mode reset-request path. See the note under each finding. It covers one audit pass; it is not a comprehensive statement of the application's security posture.

---

## Bottom line

The recent full-mode (Rodauth) auth hardening work is well-engineered and fail-secure by design — no defects found in that code itself. However, all of it targets **full mode only**, and the application defaults to **simple mode** (`lib/onetime/auth_config.rb:40`, `return 'simple' unless ...`). Two hardening features that already exist for full mode were never backported to the default mode, reopening one previously-fixed issue. Both have since been backported (see the updates under each finding); the structural lesson stands — a control added behind a Rodauth hook does not exist in the mode most deployments run.

---

## Findings

### 1. HIGH — Password change/reset does not revoke other sessions in simple (default) mode — **FIXED same-day, see update**

**Files (as of audit time, commit `e6a6e46d`):** `apps/api/account/logic/account/update_password.rb:50-52` (`perform_update`), `apps/api/account/logic/authentication/reset_password.rb:72` (`@cust.update_passphrase @password`)

When `Onetime.auth_config.full_enabled?` is false (the default), `UpdatePassword#perform_update` calls `cust.update_passphrase!` directly (`lib/onetime/models/features/passphrase_hashing.rb:32`), and the self-service `ResetPassword` logic calls `@cust.update_passphrase`. Neither path calls a session-revocation operation, and neither writes `Customer#last_password_update` (`lib/onetime/models/customer.rb:170`) — that field is set *only* by `Auth::Operations::UpdatePasswordMetadata`, invoked solely from the Rodauth `after_change_password`/`after_reset_password` hooks (`apps/web/auth/config/hooks/account.rb`), i.e. full mode only.

Because the field stays 0 for simple-mode customers, `session_predates_credential_change?` (`lib/onetime/application/auth_strategies/helpers.rb:71-72`) always short-circuits to `false`, so neither the immediate active-session kill nor the #3810 watermark-based defense-in-depth check ever fires for simple-mode accounts. A stolen/compromised session survives the victim's own password change or reset for the full session TTL (up to 24h).

This was a direct regression of the already-"Fixed" M-2 finding from the 2026-07-06 audit, scoped specifically to the mode most deployments actually run.

**Original recommended fix:** In simple mode, call a session-revocation operation from `UpdatePassword#perform_update` and `ResetPassword#process`, and stamp a credential-change watermark on both paths.

**Update — resolved:** PR #3949 (commit `2793e644`, "revoke sessions on password change/reset in simple mode") shipped the fix the same day this report was opened, landing on `main` before this report's own PR merged. It added `Onetime::Logic::CredentialChangeSessionRevocation` (`lib/onetime/logic/credential_change_session_revocation.rb`), included into both logic classes: `ResetPassword#process` now calls `revoke_sessions_for_credential_change(@cust)` at line 93 (all sessions revoked — the requester is unauthenticated), and `UpdatePassword#perform_update` calls `revoke_other_sessions_simple_mode` (line 55), which revokes every *other* session while rotating and re-stamping the caller's own session past the new watermark. Verified against current source; this finding is closed.

### 2. MEDIUM — No rate limiting on `/auth/reset-password-request` in simple (default) mode — **FIXED, see update**

**File:** `apps/api/account/logic/authentication/reset_password_request.rb`, routed via `apps/web/core/routes.txt:33` → `Core::Controllers::Registration#request_reset_email`

Issue #3872 (commits `ab81d3d`/`930ce71`) added a per-IP + per-target rate limiter (`Onetime::Security::ResetRequestRateLimiter`), but it's wired only into `apps/web/auth/config/hooks/reset_password_request.rb`, loaded solely when `full_enabled?` (`lib/onetime/application/registry.rb:157-159` skips `web/auth/` otherwise). The simple-mode logic class has no limiter call at all. `ResetPasswordRequest#process` already returns identical responses for existing/non-existing accounts (good), but with no throughput cap an attacker can mail-bomb arbitrary addresses and accumulate unlimited samples against the residual timing side-channel already documented at the top of that file. Same root cause and parity gap as finding #1.

**Fix:** Add the same `ResetRequestRateLimiter` check (keyed the same way) into `Core::Controllers::Registration#request_reset_email` / `ResetPasswordRequest#raise_concerns`.

**Update — resolved:** `AccountAPI::Logic::Authentication::ResetPasswordRequest` now includes `Onetime::Security::ResetRequestRateLimiter` and calls `enforce_reset_request_rate_limit!(reset_request_client_ip, @login_or_email)` as the FIRST statement of `#raise_concerns` — ahead of the `valid_email?` format check and ahead of the `Onetime::Customer.find_by_email` lookup in `#process`, matching the full-mode hook's before-the-route-body ordering. The per-IP subject is the strategy-metadata client IP (`AuthStrategies::Helpers#client_ip` → `env['otto.client_ip']`, the trusted-proxy-resolved and privacy-masked value the hook also reads). The per-login subject is the sanitized login actually used for the lookup — deliberately not byte-identical to the hook's raw param, since each mode keys on the string *it* resolves accounts with, which is what keeps the backstop bucket 1:1 with that mode's lookup; the divergence only merges submissions into one bucket, never splits a target across several. No new enumeration oracle is introduced: the limiter keys only on request-observable inputs. `Onetime::LimitExceeded` is not an `OT::FormError`, so it bypasses the controller's form-error rescue and reaches the Otto handler registered in `lib/onetime/application/otto_hooks.rb`, rendering the ADR-013 429 with `retry_after`. Covered by `spec/integration/simple/reset_password_request_rate_limit_spec.rb` (real HTTP through the mounted Core app: per-IP tier keyed on the masked client IP with per-source isolation, per-login backstop, 429 enumeration symmetry, no lookup/dispatch once locked, and the shipped no-config default being ON) and unit coverage in `apps/api/account/spec/logic/authentication/reset_password_request_spec.rb`. This finding is closed.

**Scope of that closure — adjacent gap still open.** The fix covers `POST /auth/reset-password-request` only. `POST /auth/create-account` (`apps/api/account/logic/account/create_account.rb`, simple mode, unauthenticated) reaches a comparable side-effect chain — `Customer.find_by_email`, a verification-secret write that overwrites `cust.reset_secret`, and a mail dispatch to a caller-chosen address, resent on every request for an existing unverified account — and `#raise_concerns` there enforces no rate limit of any kind. Mail-bombing and existence-sampling via that route remain unbounded in the default configuration. Not filed as part of finding #2 (different endpoint, not assessed in this audit pass); worth its own issue.

---

## Explicitly re-checked, not re-filed

- `identity_resolution.rb:104` (`session['account_external_id']`) — still present, still dead/inert as previously noted; not newly relevant.
- Session cookie CSRNG/HttpOnly/`cookie_only`, sendgrid-ruby dead code, Renovate lockfile cooldown, suspended-account rejection coverage, UTF-8 sanitizer dead code — all still correctly refuted/dead from the 2026-07-19 pass, unchanged.
- The #3810 rotation/watermark logic, #3840 SSO mailbox-proof linking, #3856 invite-enumeration fix, Stripe webhook signature/replay validation, and `StripeOrganizations`/billing federation code were read closely; no defects found.
- No hardcoded secrets, no `Marshal.load`/unsafe `YAML.load`/`eval` on untrusted input, no SQL string-interpolation injection found in the delta since 2026-07-19.

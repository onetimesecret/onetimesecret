# Authentication & Session Management — Security Assessment

**Target:** OneTimeSecret (main app + `otto`, `familia`, fork of `rodauth`, fork of `rodauth-omniauth`)
**Branch:** `claude/vigilant-goldberg-97ijfl`
**Scope:** Authentication & session management (Rodauth config, magic-link/email-auth, SSO/OIDC, WebAuthn, TOTP/MFA, session lifecycle, lockout/reset/enumeration)
**Assessment type:** Authorized defensive source review + local reasoning. Synthetic data only. READ-ONLY on tracked sources.
**Date:** 2026-06-22

Severity legend: Critical / High / Medium / Low / Info. Status: **CONFIRMED** (verified in code) vs **NEEDS-VALIDATION** (mechanism confirmed; exploitability depends on runtime/deploy config).

---

## Executive Summary

The auth stack is generally thoughtfully built: Rodauth tokens use 256-bit entropy with HMAC-at-rest and constant-time comparison; the partial-MFA session state is correctly gated by the main app; account creation and email-auth/verify-resend flows are hardened against enumeration; and the multi-tenant SSO credential-injection path has solid cross-tenant guards. However, several high-impact issues exist, concentrated in SSO and email-link generation.

### Top findings

| # | Finding | Severity | Status |
|---|---------|----------|--------|
| 1 | SSO identity auto-links to existing local account by email; no `email_verified` check → account takeover | **Critical** | CONFIRMED |
| 2 | SSO logins unconditionally bypass MFA (`via_omniauth: true`) | **High** | CONFIRMED |
| 3 | Host-header poisoning of reset/magic/verify email links → token theft / ATO | **High** | CONFIRMED |
| 4 | SSO domain/allowlist restriction not applied on the account-*linking* path | **High** | CONFIRMED |
| 5 | Recovery codes stored in plaintext in SQL | **Medium** | CONFIRMED |
| 6 | WebAuthn RP-ID & origin derived from attacker-controllable Host header | **Medium** | NEEDS-VALIDATION |
| 7 | Password-reset request leaks account existence/state (401/403/200) | **Medium** | CONFIRMED |
| 8 | No maximum password length → argon2 CPU/memory DoS | **Medium** | CONFIRMED |
| 9 | Per-account lockout (5 fails, ~1-day default) → targeted victim DoS | **Medium** | CONFIRMED |
| 10 | SSO default config applies NO domain restriction (default-allow) | **Medium** | CONFIRMED |
| 11 | OIDC id_token nonce can be overridden by callback param | **Medium** | NEEDS-VALIDATION |
| 12 | Email-token DB hashing depends on `AUTH_SECRET`; raw-token fallback if unset | **Medium** | NEEDS-VALIDATION |
| 13 | Recovery codes only 64-bit entropy; only 4 issued | **Low** | CONFIRMED |
| 14 | No breach/common-password/complexity checks (features exist, unused) | **Low** | CONFIRMED |
| 15 | Login timing oracle (argon2 only runs for existing accounts) | **Low** | NEEDS-VALIDATION |
| 16 | WebAuthn UV `preferred` (not enforced), incl. passwordless login | **Low** | CONFIRMED |
| 17 | Stateless WebAuthn challenge, no single-use ledger | **Low** | CONFIRMED |
| 18 | Tenant-controlled OIDC issuer/discovery (per-domain SSO) | **Low/Medium** | NEEDS-VALIDATION |
| 19 | `IdentityResolution.full_authenticated?` omits `authenticated==true` check | **Info** | CONFIRMED (dead path) |

### Positive controls observed
- Session ID is regenerated on login (Rodauth `update_session` → `clear_session` → `session.destroy` → new sid), mitigating fixation.
- Session data is AES-256-GCM encrypted + HMAC-signed at rest in Redis (`lib/onetime/session.rb`), keys derived via HKDF (`lib/onetime/key_derivation.rb`).
- The partial-auth (`awaiting_mfa`) state is correctly NOT treated as authenticated by the app's real gate.
- Account creation, email-auth request, and verify-account resend are enumeration-safe.
- TOTP replay within the time-step is prevented; OTP keys HMAC-wrapped; multi-tenant SSO has cross-tenant mismatch/strategy validation.

---

## 1. CRITICAL — SSO identity auto-links to an existing local account by email, with no IdP email-verification check

**Status:** CONFIRMED (behavior). Real-world exploitability depends on a deployment trusting an IdP whose asserted email the attacker can control.

**Evidence:**
- `apps/web/auth/config/hooks/omniauth.rb:27-30` — `account_from_omniauth` resolves an **existing** account purely by normalized email:
  ```ruby
  auth.account_from_omniauth do
    normalized_email = OT::Utils.normalize_email(omniauth_email)
    _account_from_login(normalized_email)
  end
  ```
- `rodauth-omniauth` fork `lib/rodauth/features/omniauth.rb:58-99` — callback links the SSO identity to whatever account that returns, then `login("omniauth")`. No email-ownership proof.
- `apps/web/auth/config/features/omniauth.rb:38-40` — `auth.omniauth_verify_account? true` overrides the upstream guard (`account[login_column] == omniauth_email`, fork `omniauth.rb:151-153`), so even an unverified pre-existing account is force-verified and logged into.
- `rodauth-omniauth` `lib/rodauth/omniauth_base.rb` — `omniauth_email` is just `auth_hash.info.email`; **no `email_verified` claim is ever read** anywhere in OTS production code (verified by grep — appears only in spec fixtures). The OIDC strategy exposes `info.email_verified` but OTS never consults it.

**Impact:** An attacker who can cause any trusted/enabled IdP to assert `email == victim@domain` (e.g., a self-service or attacker-administered tenant IdP, or a provider that returns unverified emails) is logged in as the victim into the victim's pre-existing password-protected account — bypassing the password and (combined with Finding 2) the victim's MFA. Classic SSO-merge / pre-hijack account takeover.

**Remediation:**
1. Read and require the IdP `email_verified` claim before trusting the email for link/create.
2. Do not silently auto-link an SSO identity to an account that already has its own credentials (password/email-auth/WebAuthn). Require an explicit linking confirmation (login or emailed link).
3. Replace `omniauth_verify_account? true` with a predicate that re-asserts the upstream `account[login_column] == omniauth_email` guard AND `email_verified`.

---

## 2. HIGH — SSO logins unconditionally bypass MFA

**Status:** CONFIRMED.

**Evidence:**
- `apps/web/auth/config/hooks/login.rb:128-133` — `after_login` passes `via_omniauth: true` for SSO.
- `apps/web/auth/operations/detect_mfa_requirement.rb:151-156` — `mfa_required?` returns `false` immediately when `@via_omniauth` is true, *before* any policy override:
  ```ruby
  return false if @via_omniauth
  return true if @mfa_policy == :required
  ```

**Impact:** An account that has TOTP/recovery configured is logged in with a full session via SSO **without** a second factor. Combined with Finding 1, an attacker who takes over the SSO email-match path also skips the victim's MFA entirely. Even on its own, this means MFA is not enforced for SSO users — an explicit project decision ("the IdP is trusted"), but it silently overrides an account-level `:required` MFA policy.

**Remediation:** At minimum, honor an account-level `mfa_policy == :required` even for SSO (do not let `via_omniauth` short-circuit a hard requirement). Document the SSO-skips-MFA behavior prominently; consider requiring the IdP to assert an MFA/`amr` claim before treating SSO as two-factor-equivalent.

---

## 3. HIGH — Host-header poisoning of password-reset / magic-link / verify-account email links

**Status:** CONFIRMED (mechanism + absence of edge enforcement in app code). Net exploitability depends on whether the production edge proxy strictly pins `Host`.

**Evidence:**
- Email link bodies use `request.base_url` directly:
  - `apps/web/auth/config/email/reset_password.rb:14-15` (`reset_password_path: reset_password_email_link`, `baseuri: request.base_url`)
  - `apps/web/auth/config/email/email_auth.rb:20`
  - `apps/web/auth/config/email/verify_account.rb:15`
- Rodauth builds the token link host from the request: fork `rodauth/lib/rodauth/features/email_base.rb:53-55` → `base.rb` `domain`/`base_url` derive from `request.host` (the inbound `Host` header). OTS does **not** override `auth.domain`/`auth.base_url` (verified by grep over `apps/web/auth/config`).
- `Rack::DetectHost` only writes `env['rack.detected_host']` (`lib/middleware/detect_host.rb:192`); it does **not** rewrite `HTTP_HOST` or reject bad hosts.
- `Onetime::Middleware::DomainStrategy#call` (`lib/onetime/middleware/domain_strategy.rb:104-149`) classifies a bad host as `:invalid` but still calls `@app.call(env)` (line 146) — it does not halt untrusted hosts.

**Impact:** If an attacker can set the `Host` header on the request that triggers a reset/magic-link email for a victim, the victim receives a legitimate email whose link points to `https://attacker.example/reset-password?key=<account_id>_<valid_key>`. Clicking it delivers the valid single-use token to the attacker → password reset / passwordless login → account takeover.

**Remediation:** Override Rodauth `domain`/`base_url` (and the template `baseuri`) to a configured canonical site host (e.g. `OT.conf['site']['host']` / `DomainStrategy.canonical_domain`), or strictly validate/reject non-allowlisted `Host` at the edge AND in `DomainStrategy` (halt on `:invalid`). Do not derive email-link hosts from `request.host`.

---

## 4. HIGH — SSO domain/allowlist restriction not applied to the account-linking path

**Status:** CONFIRMED.

**Evidence:**
- Domain validation lives only in `before_omniauth_create_account` (`apps/web/auth/config/hooks/omniauth.rb:133-180`).
- Fork `rodauth-omniauth/lib/rodauth/features/omniauth.rb:79-87` runs `omniauth_create_account` (and thus `before_omniauth_create_account`) **only when no account was found**. When `account_from_omniauth` matches an existing account by email, creation — and the entire domain check — is skipped.

**Impact:** Allowed-domain / per-domain SignupConfig restrictions are bypassable for any email that already has an OTS account. An out-of-policy IdP identity can still authenticate into a pre-existing account regardless of the configured domain allowlist (amplifies Finding 1).

**Remediation:** Apply the domain/policy validation on the linking path too (e.g., in `before_omniauth_callback_route` or inside `account_from_omniauth`), not only on creation.

---

## 5. MEDIUM — Recovery codes stored in plaintext in SQL

**Status:** CONFIRMED.

**Evidence:**
- Rodauth `recovery_codes` feature stores `new_recovery_code` verbatim (`rodauth/lib/rodauth/features/recovery_codes.rb:~189-196` insert) and reads it back with `select_map(recovery_codes_column)` (~263), comparing via `timing_safe_eql?` against the raw stored value. No HMAC/hash is applied (unlike password hashes and HMAC-wrapped OTP keys).
- OTS overrides only the generator (`apps/web/auth/config/features/mfa.rb:74-76`), not storage.

**Impact:** Recovery codes are full MFA-bypass credentials sitting in cleartext in the auth DB. DB read access (compromise, backup leak, SQLi, broad console access) yields working second-factor bypass codes.

**Remediation:** Store a keyed hash/HMAC of recovery codes (verify whether this Rodauth version honors `hmac_secret` for recovery codes; if not, override `add_recovery_code`/`recovery_code_match?` to HMAC before store/compare). Enforce DB-at-rest encryption and tight access on `account_recovery_codes` + backups.

---

## 6. MEDIUM (NEEDS-VALIDATION) — WebAuthn RP-ID and origin derived from attacker-controllable Host header

**Status:** Mechanism CONFIRMED; impact depends on edge `Host` enforcement.

**Evidence:**
- `apps/web/auth/config/features/webauthn.rb:14-22` — `webauthn_rp_id { request.host }` and `webauthn_origin { "#{request.scheme}://#{request.host_with_port}" }`.
- Both the expected RP-ID and the expected origin track the same request host, so a mismatched/attacker host does not fail verification — the "expected" values simply move to match. The codebase already computes a validated canonical host (`env['onetime.display_domain']`) but WebAuthn does not use it.

**Impact:** Weakens WebAuthn's anti-phishing origin pinning to "origin must equal whatever host this request claims." If any unvalidated host reaches the app (see Finding 3 — edge does not pin), a credential registered for host A could be asserted against host B and ceremonies run under an attacker-chosen RP-ID. (Assertion replay is still blocked by `sign_count`.)

**Remediation:** Pin `webauthn_rp_id` to the configured canonical domain; validate `request.host`/origin against an allowlist (reuse `env['onetime.display_domain']`). For custom-domain support use an explicit per-domain RP-ID map.

---

## 7. MEDIUM — Password-reset request leaks account existence/state

**Status:** CONFIRMED.

**Evidence:**
- Rodauth `reset_password` (`rodauth/lib/rodauth/features/reset_password.rb:74-94`): nonexistent login → `:no_matching_login` → **401** "no matching login"; existing → **200** "email sent"; existing-but-unverified → **403** "unverified" (`:178-180`).
- OTS overrides `email_auth_request_error_flash` but NOT `reset_password_request_error_flash`/`no_matching_login_message`, and does not force a uniform 200 (verified by grep). With `only_json? true`, the attacker reads status/message and distinguishes nonexistent (401) vs unverified (403) vs valid (200).

**Impact:** Email/account enumeration plus account-state disclosure via the public reset endpoint. (Note: account creation, email-auth request, and verify-resend are enumeration-safe — see positives.)

**Remediation:** Make the reset-request response uniform (always 200 + generic "if an account exists, an email was sent"), mirroring the generic treatment already applied to create-account/email-auth.

---

## 8. MEDIUM — No maximum password length → argon2 resource-exhaustion DoS

**Status:** CONFIRMED.

**Evidence:**
- `apps/web/auth/config/features/account_management.rb:104` sets `password_minimum_length 8` but **no** `password_maximum_length`/`password_maximum_bytes` exists anywhere (grep). Rodauth defaults are `nil`.
- The raw password is fed to `::Argon2::Password...create(password)` (`apps/web/auth/config/features/argon2.rb`) on every signup/reset/change, with production cost `t_cost=2, m_cost=16` (64 MiB). Argon2 has no inherent input truncation (unlike bcrypt's 72 bytes).

**Impact:** Multi-megabyte passwords multiply CPU/memory per hash; repeated large-password POSTs to signup/reset are a cheap DoS, amplified by synchronous email `fallback: :sync` (`config/email/delivery.rb:38`).

**Remediation:** Set `auth.password_maximum_bytes` (e.g., 256–1024).

---

## 9. MEDIUM — Per-account lockout enables targeted victim DoS

**Status:** CONFIRMED.

**Evidence:**
- `apps/web/auth/config/features/lockout.rb:15` — `max_invalid_logins 5`; the `lockout_expiration_default` override is commented out (`:16`), so the Rodauth default `account_lockouts_deadline_interval {:days=>1}` (~1 day) applies.
- Rodauth lockout is keyed on `account_id` and blocks `before_login_attempt` once locked.

**Impact:** Knowing a victim's email, an attacker submits 5 bad passwords to lock that account for ~1 day. Self-service unlock exists via the unlock-account email flow, but still forces a victim email round-trip. (Passwordless paths — magic link / SSO — and reset are not gated by lockout, which is generally desirable but means lockout doesn't stop a factor-pivoting attacker.)

**Remediation:** Shorten the lockout window (e.g., 15–60 min with backoff), and/or add IP-based throttling and CAPTCHA so a single account isn't trivially DoS-able by a remote actor.

---

## 10. MEDIUM — SSO default configuration applies NO domain restriction

**Status:** CONFIRMED.

**Evidence:**
- `lib/onetime/config.rb` — `allowed_signup_domains` defaults to `[]`; `Onetime::SignupValidation.global_allowed_domains?` returns `true` (allow-all) for an empty list (`lib/onetime/signup_validation.rb`).
- `apps/web/auth/config/features/omniauth.rb:42-47` — `omniauth_create_account? true`.
- Normalization mismatch: lookup uses full `normalize_email` (NFC + `:fold`) at `hooks/omniauth.rb:28`, but the domain-policy check uses `.strip.downcase` (`hooks/omniauth.rb:134`, `signup_validation.rb`). Unicode/fold-equivalent emails can diverge between policy and match.

**Impact:** Default posture is open auto-provisioning for any user of a trusted IdP. Operators relying on SSO to restrict to their org are unprotected unless they explicitly configure allowlists. The normalization mismatch is a potential allowlist-bypass vector (NEEDS-VALIDATION as an independent exploit).

**Remediation:** Ship a safer default (require an allowlist when SSO + auto-create are enabled); use the same `normalize_email` for both policy checks and account lookup.

---

## 11. MEDIUM (NEEDS-VALIDATION) — OIDC id_token nonce can be overridden by callback param

**Status:** NEEDS-VALIDATION (upstream `omniauth_openid_connect` behavior).

**Evidence:**
- `omniauth_openid_connect` strategy verifies id_token with `nonce: params['nonce'].presence || stored_nonce` — a callback-supplied `nonce` param overrides the session `stored_nonce`, weakening the session↔id_token nonce binding.

**Impact:** Nonce replay protection can be neutralized by an attacker controlling callback params with a known-nonce id_token. In OTS's code+PKCE flow, OAuth `state` and PKCE still protect primary CSRF/code-injection, so this is defense-in-depth (Medium), not standalone takeover.

**Remediation:** Pin/patch the OIDC strategy to verify id_token nonce strictly against `stored_nonce` (ignore `params['nonce']`), or upgrade if upstream is fixed.

---

## 12. MEDIUM (NEEDS-VALIDATION) — Email-token DB hashing depends on `AUTH_SECRET`; raw-token fallback if unset

**Status:** NEEDS-VALIDATION (`rodauth-tools` `hmac_secret_guard` source not on disk).

**Evidence:**
- Tokens are HMAC-SHA256 in the DB **only if** `hmac_secret` is set. OTS sets it indirectly via `auth.hmac_secret_env_key 'AUTH_SECRET'` + `enable :hmac_secret_guard` (`apps/web/auth/config/base.rb:10-13`).
- If `AUTH_SECRET` is unset/empty and `hmac_secret_guard` does not hard-fail boot, `hmac_secret` falls back to `nil` (rodauth `base.rb:44`), and `account_from_key` accepts a **raw** token compared against the raw stored key (fork `email_base.rb:74`, `(!hmac_secret || allow_raw_email_token?)` branch) — i.e., DB-readable tokens become directly usable.

**Impact:** With no/empty `AUTH_SECRET`, magic-link/reset/verify tokens are stored in cleartext and a DB read yields usable login/reset tokens.

**Remediation:** Confirm `hmac_secret_guard` raises on boot when `AUTH_SECRET` is missing; make a strong `AUTH_SECRET` mandatory in production via a boot assertion.

---

## 13. LOW — Recovery codes only 64-bit entropy; only 4 issued

**Status:** CONFIRMED.

**Evidence:**
- `apps/web/auth/config/features/mfa.rb:74-76` — `new_recovery_code { Familia.generate_trace_id }`; `generate_trace_id` is a 64-bit CSPRNG value (`familia/lib/familia/secure_identifier.rb`), which Familia explicitly labels "NOT safe for security contexts." Only 4 codes (`RECOVERY_CODES_LIMIT = 4`, `mfa.rb:14`).

**Impact:** 2^64 keyspace per code, below the typical 128-bit recommendation. Mitigated by single-use deletion, account binding, and rate limiting — but confirm the recovery-auth endpoint (not just the OTP route, `OTP_AUTH_FAILURES_LIMIT = 7`) is itself lockout-protected; the `before_recovery_auth` hook only logs.

**Remediation:** Use 128-bit codes; confirm recovery-auth is rate-limited/locked out.

---

## 14. LOW — No breach/common-password/complexity checks

**Status:** CONFIRMED.

**Evidence:** `apps/web/auth/config/features/password_requirements.rb` enables only `login_password_requirements_base`. The fork ships `disallow_common_passwords`, `password_complexity`, `disallow_password_reuse`, `password_pepper` — OTS enables none. No HaveIBeenPwned/k-anonymity check. 8-char minimum permits weak/breached passwords.

**Remediation:** Enable `disallow_common_passwords` and/or a pwned-passwords integration.

---

## 15. LOW (NEEDS-VALIDATION) — Login timing oracle (argon2 only for existing accounts)

**Status:** NEEDS-VALIDATION.

**Evidence:** Rodauth `_account_from_login` short-circuits before password hashing for nonexistent logins, so a real account pays the argon2 cost (tens of ms) and a nonexistent one does not. No dummy-hash by default.

**Impact:** Measurable timing oracle for account existence on the login endpoint.

**Remediation:** Perform a constant-time dummy argon2 verify on the no-match path.

---

## 16. LOW — WebAuthn user verification `preferred` (not enforced), including passwordless login

**Status:** CONFIRMED.

**Evidence:** `apps/web/auth/config/features/webauthn.rb:32` — `webauthn_user_verification 'preferred'`; `:9,44` enables `webauthn_login` (passwordless). With `preferred`, the UV flag is not required.

**Impact:** Passwordless WebAuthn can succeed with user-presence only (no biometric/PIN) — single-factor possession login without guaranteed user verification.

**Remediation:** For passwordless/primary WebAuthn, set `webauthn_user_verification 'required'`.

---

## 17. LOW — Stateless WebAuthn challenge, no single-use ledger

**Status:** CONFIRMED (Rodauth design).

**Evidence:** Challenge + `compute_hmac(challenge)` sent to the client; verification recomputes the HMAC (`timing_safe_eql?`) and the gem verifies the assertion. The challenge is never persisted server-side and carries no nonce/expiry.

**Impact:** Challenge is random and unforgeable, but a captured valid `{challenge, hmac, assertion}` stays structurally acceptable until `AUTH_SECRET` rotates. Practical replay is blocked by `sign_count`; the gap is the absence of an independent freshness control. `webauthn_*_timeout` values are client-side hints only.

**Remediation:** Accept as a known tradeoff, or add a short-TTL stateful challenge ledger; ensure `AUTH_SECRET` rotation procedures exist.

---

## 18. LOW/MEDIUM (NEEDS-VALIDATION) — Tenant-controlled OIDC issuer/discovery (per-domain SSO)

**Status:** Cross-tenant credential reuse = CONFIRMED MITIGATED; tenant-issuer trust = NEEDS-VALIDATION.

**Evidence (mitigations are strong):**
- `apps/web/auth/config/hooks/omniauth_tenant.rb:64-78,145-151` — tenant context stored only in request phase, not overwritten on callback.
- `omniauth_tenant.rb:177-214` — callback re-resolves host, 403 on `domain_id` mismatch.
- `omniauth_tenant.rb:312-340` — strategy-class validation before credential injection (`STRATEGY_CLASS_MAP`), 400 on mismatch.
- `lib/onetime/models/custom_domain/sso_config.rb` — credentials encrypted with AAD bound to `domain_id`; host lookup is exact downcased index membership.
- `lib/onetime/auth_config.rb:244-246` — `allow_platform_fallback_for_tenants?` defaults `false`.

**Residual risk:** A tenant's OIDC `issuer` is tenant-controlled and (with `discovery: true`) dictates the trust target. Crossed with Findings 1/2/4, a malicious tenant admin could configure an issuer asserting arbitrary verified-looking emails and link into accounts whose email matches another user (especially canonical-domain accounts). Identity links and login are global per the `accounts` table even though org-join is tenant-scoped.

**Remediation:** Enforce `email_verified` + explicit linking (Findings 1/4); constrain tenant-IdP-authenticated identities to the tenant org boundary at the session/authorization layer; optionally allowlist tenant `issuer` hosts.

---

## 19. INFO — `IdentityResolution.full_authenticated?` omits the `authenticated == true` check (dead path)

**Status:** CONFIRMED (latent; no current impact).

**Evidence:**
- `lib/onetime/middleware/identity_resolution.rb:259-267` — `full_authenticated?` checks `authenticated_at` and (`external_id` OR `account_id`) but **not** `authenticated == true`.
- `:104` then looks up the customer by `session['account_external_id']` — a key **never set** by the auth flow (only `external_id` is set). So `find_by_extid(nil)` returns nil → `no_identity`. The path is effectively dead.
- `env['identity.authenticated']` has **no consumers** in `lib/` or `apps/` (grep). The real gate is `BaseSessionAuthStrategy` (`lib/onetime/application/auth_strategies/base_session_auth_strategy.rb:33-39`), which correctly requires `authenticated == true` + `external_id`.

**Impact:** None today. If a future change ever wires this middleware's result into authorization, or sets `account_external_id`, the weak `full_authenticated?` predicate would grant access to `awaiting_mfa`/partial sessions.

**Remediation:** Fix `full_authenticated?` to require `session['authenticated'] == true`; correct or remove the `account_external_id` lookup. Defense-in-depth: have the session strategy also treat `awaiting_mfa == true` as not-authenticated regardless of the `authenticated` flag.

---

## Session lifecycle notes (mostly positive)

- **Fixation:** Mitigated. On login, Rodauth `update_session` calls `clear_session` (overridden to `session.destroy`, `apps/web/auth/config/base.rb:74-76`), and OTS's `delete_session` generates a new sid (`lib/onetime/session.rb:131-168`), so the cookie sid rotates before `account_id` is written.
- **Confidentiality/integrity:** Session data is AES-256-GCM + HMAC-SHA256 over Redis `StringKey`, HKDF-derived keys (`session.rb`, `key_derivation.rb`). Constant-time HMAC compare (`session.rb:213`). Sound.
- **Privilege change on MFA:** `PrepareMfaSession` sets only `account_id`/`email` (not `authenticated`/`external_id`); `SyncSession` sets the full authenticated session and clears `awaiting_mfa` post-MFA. Correct.
- **Logout:** `clear_session` → `session.destroy` deletes the Redis key and rotates the cookie. Logout invalidates the current session only (standard). Note two parallel session ledgers exist: the Rack/Redis session and Rodauth's `account_active_session_keys` (HMAC'd) for the active-sessions feature.
- **Remember-me:** Defaults inherited (14-day cookie, `extend_remember_deadline? false`) — `apps/web/auth/config/features/remember_me.rb`. Validate remember tokens are invalidated on password change/close-account.

---

## Suggested remediation priority

1. **SSO core (Findings 1, 2, 4, 10):** Enforce `email_verified`; require explicit account-linking confirmation; apply domain policy on the link path; safer default allowlist; honor `mfa_policy == :required` for SSO. This single workstream addresses the most serious, chained risk.
2. **Email-link host pinning (Finding 3):** Override `domain`/`base_url`/`baseuri` to canonical host; halt invalid hosts at the edge/DomainStrategy. Also fixes Finding 6 (WebAuthn RP-ID/origin) if the canonical host is reused there.
3. **Recovery codes (Findings 5, 13):** HMAC at rest, raise to 128-bit, confirm recovery-auth lockout.
4. **DoS/enumeration hardening (Findings 7, 8, 9, 15):** Uniform reset response, `password_maximum_bytes`, shorter lockout + IP throttle, dummy argon2 on no-match.
5. **Config assertions (Finding 12):** Hard-fail boot without a strong `AUTH_SECRET`.

---

*Files of interest (absolute):*
`/home/user/onetimesecret/apps/web/auth/config/hooks/omniauth.rb`,
`/home/user/onetimesecret/apps/web/auth/config/hooks/omniauth_tenant.rb`,
`/home/user/onetimesecret/apps/web/auth/config/hooks/login.rb`,
`/home/user/onetimesecret/apps/web/auth/operations/detect_mfa_requirement.rb`,
`/home/user/onetimesecret/apps/web/auth/operations/{prepare_mfa_session,sync_session,mfa_state_checker}.rb`,
`/home/user/onetimesecret/apps/web/auth/config/features/{omniauth,webauthn,mfa,lockout,password_requirements,account_management}.rb`,
`/home/user/onetimesecret/apps/web/auth/config/email/{reset_password,email_auth,verify_account,delivery}.rb`,
`/home/user/onetimesecret/apps/web/auth/config/base.rb`,
`/home/user/onetimesecret/apps/web/auth/config/rodauth_overrides.rb`,
`/home/user/onetimesecret/lib/onetime/session.rb`,
`/home/user/onetimesecret/lib/onetime/key_derivation.rb`,
`/home/user/onetimesecret/lib/onetime/middleware/identity_resolution.rb`,
`/home/user/onetimesecret/lib/onetime/middleware/domain_strategy.rb`,
`/home/user/onetimesecret/lib/onetime/application/auth_strategies/base_session_auth_strategy.rb`,
`/home/user/rodauth-omniauth/lib/rodauth/features/omniauth.rb` (clean upstream v0.6.2),
`/home/user/rodauth/lib/rodauth/features/{base,email_base,email_auth,reset_password,otp,recovery_codes,webauthn}.rb`.

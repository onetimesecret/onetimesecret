# Security Audit Report: Onetimesecret

**Date:** 2026-07-06
**Scope:** Full application security audit across 6 repositories
**Method:** Static analysis and code review (no runtime testing)

## Repositories Audited

| Repository                     | Branch                            | Commit    |
| ------------------------------ | --------------------------------- | --------- |
| onetimesecret/onetimesecret    | `claude/eager-brahmagupta-ha5uo6` | `260be4a` |
| delano/familia                 | `claude/amazing-goodall-ha5uo6`   | `df9992b` |
| delano/otto                    | `claude/upbeat-planck-ha5uo6`     | `bbc59eb` |
| onetimesecret/rodauth          | `claude/dreamy-babbage-ha5uo6`    | `2732c44` |
| onetimesecret/rodauth-omniauth | `claude/magical-feynman-ha5uo6`   | `9fe8152` |
| onetimesecret/rhales           | `claude/magical-euler-ha5uo6`     | `ca79eaf` |

## Coverage

| Focus Area                | Status  |
| ------------------------- | ------- |
| Auth & session management | Covered |
| Authorization / IDOR      | Covered |
| Redis-specific risks      | Covered |
| REST API security         | Covered |
| SPA security              | Covered |
| Supply chain              | Covered |
| Runtime / deployment      | Covered |
| Business logic            | Covered |
| Cryptography              | Covered |
| Observability             | Covered |

---

## Executive Summary

The application demonstrates strong security engineering overall. The core product promise -- burn-after-reading -- is protected by an atomic compare-and-set Lua script in Redis that correctly prevents double-reveal races. Session management uses AES-256-GCM encryption with HMAC signing and HKDF-derived keys. Identifier generation uses 256-bit CSPRNG. Input sanitization is thorough and multi-pass. XSS is mitigated by textarea-based rendering and DOMPurify for the single v-html usage.

The most significant findings are in deployment configuration defaults (security middleware disabled, Redis unauthenticated) and an API-wide CSRF bypass that affects session-authenticated API v2/v3 requests. No critical vulnerabilities were found in the application logic itself.

**Finding Summary:**

| Severity      | Count | Fixed | Accepted | Open |
| ------------- | ----- | ----- | -------- | ---- |
| Critical      | 0     | 0     | 0        | 0    |
| High          | 3     | 3     | 0        | 0    |
| Medium        | 11    | 10    | 1        | 0    |
| Low           | 10    | 0     | 0        | 10   |
| Informational | 6     | 0     | 0        | 6    |

Status columns reflect the `security/audit-2026-07-06-high-medium` branch (2026-07-17). See [Remediation Status](#remediation-status) for per-finding detail.

---

## Remediation Status

**Branch:** `security/audit-2026-07-06-high-medium` (as of 2026-07-17)

All 3 High and all 11 Medium findings are resolved on this branch, except **M-3** (accepted; V1 is maintenance-only) which is documented rather than fixed. One additional residual (#3516) was fixed by moving the login rate-limit check ahead of the Argon2 comparison. Low and Informational findings are not addressed on this branch.

| ID   | Status       | Commit(s)               | Note                                                              |
| ---- | ------------ | ----------------------- | ---------------------------------------------------------------- |
| H-1  | Fixed        | `d3f5246c2`             | CSRF token required on session-authenticated API requests        |
| H-2  | Fixed        | `1759fc294`             | Valkey/RabbitMQ credentials required in compose stacks           |
| H-3  | Fixed        | `aa3d70b2b`             | OmniAuth email auto-link to existing accounts refused            |
| M-1  | Fixed        | `2afbe890d`             | Security middleware protections default on                       |
| M-2  | Fixed        | `1eadc38e9`, `ed7acb23d`| Sessions revoked on password change/reset; fails loud            |
| M-3  | Accepted     | —                       | V1 maintenance-only; gap documented, no fix                      |
| M-4  | Fixed        | `4ccff8543`             | Two-tier login rate limiter for simple-mode auth                 |
| M-5  | Fixed        | `b56b99ddd`             | s6-overlay tarball checksums verified before extraction          |
| M-6  | Fixed        | `1759fc294`             | RabbitMQ credentials required (same change as H-2)               |
| M-7  | Fixed        | `60dd19fda`, `dcf71f3c2`| Cookie `secure` key omitted unless SSL=true; boot.rb defaults on |
| M-8  | Fixed        | `00956813d`, `06843d620`| Passphrase limiter keyed on secret+IP; per-IP keys in ops (RL-1) |
| M-9  | Fixed        | `11ff16ef8`             | Stripe checkout URLs host-allowlisted before navigation          |
| M-10 | Fixed        | `3673b9be8`             | Admin routes gated on colonel role; redirect param hardened      |
| M-11 | Fixed        | `02dd1b21d`             | Awaiting-MFA sessions blocked from authenticating                |
| #3516| Fixed        | `643c2182e`, `468e47cdf`| Argon2 DoS-amplification residual; rate-limit check moved ahead of Argon2 comparison |

Low (L-1–L-10) and Informational (I-1–I-6): **Open** — not scoped to this branch.

---

## Findings

### HIGH Severity

---

#### H-1: CSRF Protection Bypassed for All /api/ Routes Including Session-Authenticated Endpoints

**Severity:** High
**CVSS Estimate:** 7.1 (AV:N/AC:L/PR:N/UI:R/S:U/C:L/I:H/A:N)
**Category:** API Security
**File:** `lib/onetime/middleware/security.rb:137-143`

**Description:** The `AuthenticityToken` middleware's `allow_if` lambda exempts all paths starting with `/api/` from CSRF validation unconditionally:

```ruby
return true if req.path.start_with?("/api/")
```

API v2/v3 endpoints support session-based authentication via `BaseSessionAuthStrategy`. A session-authenticated POST to any `/api/v2/` or `/api/v3/` endpoint bypasses CSRF entirely.

**Impact:** An attacker hosting a malicious page can submit cross-origin form POSTs to session-authenticated API endpoints. With `SameSite=Lax` cookies, this is partially mitigated for cross-site requests, but same-site requests (from subdomains or same-site contexts) bypass this.

**Reproduction:**

1. User is logged in via session cookie
2. User visits attacker-controlled page on a subdomain or same eTLD+1 origin
3. Attacker's page submits a POST form to `/api/v2/secrets` with `Content-Type: application/x-www-form-urlencoded`
4. User's session cookie is sent; CSRF is not checked; secret is created under user's account

**Remediation:** Modify the `allow_if` lambda to only bypass CSRF when `Authorization: Basic ...` credentials are present. For session-authenticated API requests, require the `X-CSRF-Token` header.

**Status:** ✅ Fixed — `d3f5246c2`. Session-authenticated `/api/` requests now require a CSRF token.

---

#### H-2: Redis/Valkey Exposed Without Authentication in Simple Docker Compose

**Severity:** High
**CVSS Estimate:** 8.6 (AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N)
**Category:** Runtime / Deployment
**Files:** `docker/compose/docker-compose.simple.yml:57,68-69`

**Description:** The simple Docker Compose file exposes Valkey on port 6379 to the host network (`ports: '6379:6379'`) with `--bind 0.0.0.0` and no `requirepass`. Any process that can reach port 6379 can read all stored secrets, customer data, and session tokens.

**Impact:** Full data breach of all secrets and customer credentials. The full compose file already uses `expose` instead of `ports`, but originally ran Valkey without `--requirepass`; both stacks are now hardened symmetrically.

**Reproduction:**

```bash
docker compose -f docker/compose/docker-compose.simple.yml up -d
redis-cli -h <host-ip> -p 6379 KEYS '*'
```

**Remediation:** Change `ports: '6379:6379'` to `expose: ['6379']`. Add a `requirepass` directive to the Valkey command.

**Status:** ✅ Fixed — `1759fc294` (simple stack) and follow-up (full stack). Valkey `--requirepass` and RabbitMQ (M-6) credentials are now required across both compose stacks; neither publishes the datastore port to the host.

---

#### H-3: OAuth Account Linking via Email Without Identity Verification (rodauth-omniauth)

**Severity:** High
**CVSS Estimate:** 8.1 (AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:N)
**Category:** Authentication
**File:** `rodauth-omniauth: lib/rodauth/features/omniauth.rb:58-98,214-216`

**Description:** When an OAuth callback arrives and no `omniauth_identity` record matches the (provider, uid) pair, `_account_from_omniauth` performs a lookup by email only. If a matching account exists, the OAuth identity is linked to it automatically, granting the attacker access.

**Impact:** An attacker controlling an OAuth provider that returns a victim's email address gets their OAuth identity linked to the victim's account, enabling full account takeover.

**Preconditions:** The deployment must have OAuth/SSO enabled (disabled by default in onetimesecret). The attacker must control an OAuth provider returning the victim's email. This is a library-level finding in `rodauth-omniauth`.

**Remediation:** Override `account_from_omniauth` to return nil when no identity exists, requiring explicit user-initiated account linking while authenticated. Alternatively, require password confirmation before linking a new OAuth identity to an existing account.

**Status:** ✅ Fixed — `aa3d70b2b`. Email-based auto-linking to existing accounts is refused.

---

### MEDIUM Severity

---

#### M-1: Security Middleware Disabled by Default

**Severity:** Medium
**Category:** Runtime / Deployment
**File:** `etc/defaults/config.defaults.yaml:314-339`

**Description:** Critical security middleware defaults to disabled:

| Middleware         | Default | Protection                          |
| ------------------ | ------- | ----------------------------------- |
| `frame_options`    | OFF     | Clickjacking (X-Frame-Options)      |
| `strict_transport` | OFF     | HSTS                                |
| `path_traversal`   | OFF     | Directory traversal                 |
| `cookie_tossing`   | OFF     | Cookie manipulation from subdomains |
| `ip_spoofing`      | OFF     | X-Forwarded-For spoofing            |
| `http_origin`      | OFF     | Origin header validation            |
| `xss_header`       | OFF     | X-XSS-Protection                    |

Only `authenticity_token` (CSRF) and `utf8_sanitizer` are enabled by default.

**Impact:** A default deployment lacks clickjacking, HSTS, and path traversal protection. No warning is logged when middleware is disabled.

**Remediation:** Enable `frame_options`, `strict_transport`, and `path_traversal` by default. Log warnings when security middleware is disabled.

**Status:** ✅ Fixed — `2afbe890d`. Security middleware protections default on.

---

#### M-2: Session Not Invalidated on Password Change or Reset

**Severity:** Medium
**Category:** Authentication
**Files:** `apps/web/auth/config/hooks/password.rb:27-44`, `apps/web/auth/config/hooks/account.rb:402-414`

**Description:** After a password change or reset, existing sessions remain valid. The hooks only log the event and sync metadata. If an attacker has compromised a session, changing the password does not revoke it.

**Impact:** A compromised session survives credential rotation for up to 24 hours (inactivity deadline).

**Remediation:** Call `remove_all_active_sessions_except_current` in the `after_change_password` and `after_reset_password` hooks.

**Status:** ✅ Fixed — `1eadc38e9`, `ed7acb23d`. Sessions are revoked on password change/reset; revocation fails loud rather than silently on error.

---

#### M-3: V1 API Decrypts Secret Before Atomic Claim

**Severity:** Medium
**Category:** Business Logic
**File:** `apps/api/v1/logic/secrets/show_secret.rb:66`

**Description:** The V1 API decrypts the secret value at line 66 _before_ the atomic `revealed!` claim at line 94. A losing racer's plaintext is suppressed (lines 110-113), but it exists in Ruby process memory. The V2 API correctly decrypts only inside the won claim via `secret.reveal!`.

**Impact:** In a race condition, the plaintext exists in memory for the losing request's process lifetime. Not directly exploitable remotely, but increases the surface for memory disclosure via crashes or debugging endpoints.

**Remediation:** V1 is maintenance-only. Document the known gap. For any future work, use the V2 pattern exclusively.

**Status:** ⚪ Accepted — no code change. V1 is maintenance-only; the gap is documented and V2 already uses the correct pattern.

---

#### M-4: No Login Rate Limiting in Simple Auth Mode

**Severity:** Medium
**Category:** Authentication
**File:** `lib/onetime/helpers/session_helpers.rb:49-67`

**Description:** Rodauth's lockout feature (5 failed attempts) is only available in "full" auth mode. In "simple" mode (Redis-only), there is no brute-force protection on login.

**Impact:** Unlimited password guessing against simple-mode deployments.

**Remediation:** Add a Redis-based rate limiter to the simple-mode authentication path, similar to `PassphraseRateLimiter`.

**Status:** ✅ Fixed — `4ccff8543`. Two-tier login rate limiter added for simple-mode auth.

---

#### M-5: S6 Overlay Downloaded Without Checksum Verification

**Severity:** Medium
**Category:** Supply Chain
**File:** `Dockerfile:226-230`

**Description:** The S6 overlay is downloaded from GitHub Releases and extracted without verifying GPG signatures or SHA256 checksums. S6 runs as PID 1 in the container.

**Impact:** A compromised GitHub release would inject malicious code into the container's init process.

**Remediation:** Download and verify the `.sha256` checksum files published alongside each release.

**Status:** ✅ Fixed — `b56b99ddd`. s6-overlay tarball checksums are verified before extraction.

---

#### M-6: RabbitMQ Default `guest:guest` Credentials

**Severity:** Medium
**Category:** Runtime / Deployment
**Files:** `.env.reference:58`, `docker/compose/docker-compose.full.yml:130-132`

**Description:** RabbitMQ defaults to `guest:guest` via `${RABBITMQ_USER:-guest}` and `${RABBITMQ_PASS:-guest}`. Deployments that don't override these run a message broker with well-known credentials.

**Impact:** Any attacker with network access to the broker can intercept, inject, or delete messages including email delivery jobs.

**Remediation:** Make `RABBITMQ_USER` and `RABBITMQ_PASS` required variables (using `${VAR:?error}` syntax).

**Status:** ✅ Fixed — `1759fc294`. RabbitMQ credentials are now required in the compose stacks (same change as H-2).

---

#### M-7: Session Cookie `secure` Flag Depends on Manual Configuration

**Severity:** Medium
**Category:** Authentication
**File:** `etc/defaults/config.defaults.yaml:290-296`

**Description:** The `secure` cookie flag defaults to `ENV['SSL'] == 'true' || false`. A deployment behind HTTPS that forgets `SSL=true` serves session cookies without the `Secure` flag, exposing them to interception via HTTP downgrade.

**Remediation:** Auto-detect HTTPS from `X-Forwarded-Proto` headers. Default `secure: true` in production mode.

**Status:** ✅ Fixed — `60dd19fda`, `dcf71f3c2`. The `session.secure` key is omitted unless `SSL=true`, letting `boot.rb`'s `ssl_enabled?` fallback default it to true in production.

---

#### M-8: Passphrase Rate Limiter Enables Targeted Denial-of-Service

**Severity:** Medium
**Category:** Business Logic
**File:** `lib/onetime/security/passphrase_rate_limiter.rb:134-139`

**Description:** Rate limiter keys use only the secret identifier. Anyone with the secret link can lock out the legitimate recipient by submitting 5 wrong passphrases, blocking access for 30 minutes.

**Impact:** Targeted DoS against specific passphrase-protected secrets. Repeatable every 30 minutes.

**Remediation:** Use a compound key including client IP: `"passphrase:attempts:#{secret_identifier}:#{client_ip}"`.

**Status:** ✅ Fixed — `00956813d`, `06843d620`. Two-tier limiting keyed on secret+IP; per-IP limiter keys surfaced in ratelimit inspect/reset ops (RL-1).

---

#### M-9: `checkout_url` Redirect Without Domain Validation

**Severity:** Medium
**Category:** SPA Security
**File:** `src/apps/workspace/billing/PlanSelector.vue:264,357,394`

**Description:** The `checkout_url` from the billing API is used directly in `window.location.href = response.checkout_url` without validating it points to `checkout.stripe.com` or the application's own domain.

**Impact:** If the backend billing response is manipulated (proxy misconfiguration, API compromise), users are silently redirected to a phishing page.

**Remediation:** Add a Zod refinement validating `checkout_url` matches `https://checkout.stripe.com/` or the application domain.

**Status:** ✅ Fixed — `11ff16ef8`. Stripe checkout URLs are host-allowlisted before navigation.

---

#### M-10: Colonel Admin Panel Lacks Frontend Route Guard

**Severity:** Medium
**Category:** Authorization
**File:** `src/apps/colonel/routes.ts:6-15`

**Description:** Colonel routes use only `requiresAuth: true` with no role check. Any authenticated user can navigate to `/colonel` and see the admin UI shell. Data loads fail (backend checks role), but the UI structure, navigation, and menu labels are exposed.

**Remediation:** Add a `beforeEnter` guard checking `cust.role === 'colonel'` and redirecting non-colonels.

**Status:** ✅ Fixed — `3673b9be8`. Admin routes gated on colonel role; redirect param check hardened.

---

#### M-11: MFA `awaiting_mfa` Flag Not Checked by Auth Strategy

**Severity:** Medium
**Category:** Authentication
**Files:** `apps/web/auth/operations/prepare_mfa_session.rb:89`, `lib/onetime/application/auth_strategies/base_session_auth_strategy.rb:33`

**Description:** `PrepareMfaSession` sets `session['awaiting_mfa'] = true` alongside `session['account_id']` and `session['email']`. `BaseSessionAuthStrategy` checks only `session['authenticated']` -- not `awaiting_mfa`. Any code path treating `account_id` presence as full authentication bypasses MFA.

**Remediation:** Add `session['awaiting_mfa'] != true` to the `authenticated?` check.

**Status:** ✅ Fixed — `02dd1b21d`. Awaiting-MFA sessions are blocked from authenticating.

---

### LOW Severity

---

#### L-1: Deprecated `apitoken?` Uses Non-Constant-Time Comparison

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:63-65`
**Status:** Mitigated by Customer class override using `Rack::Utils.secure_compare`. Dead code but should be removed.

#### L-2: Minimum Password Length of 6 Characters

**File:** `apps/api/account/logic/authentication/reset_password.rb:31`
**Status:** Below modern recommendations (8-12 minimum).

#### L-3: Minimum Passphrase Length of 4 Characters

**File:** `etc/defaults/config.defaults.yaml` passphrase settings
**Status:** Low entropy for secret protection passphrases.

#### L-4: Source Maps Served in Production

**File:** `vite.config.ts:283`
**Status:** `sourcemap: true` ships `.map` files revealing full source. Use `sourcemap: 'hidden'`.

#### L-5: Redirect Validation Inconsistency

**File:** `src/router/guards.routes.ts:352-354`
**Status:** Uses simpler validation than `isValidInternalPath()` used elsewhere.

#### L-6: `useFormSubmission` Deprecated Composable Has Unvalidated Redirect

**File:** `src/shared/composables/useFormSubmission.ts:124-128`
**Status:** `window.location.href = options.redirectUrl!` without validation. Currently uses hardcoded URLs.

#### L-7: No Rehashing of Legacy BCrypt Passphrases

**File:** `lib/onetime/models/features/passphrase_hashing.rb:48-62`
**Status:** Secrets with BCrypt-hashed passphrases are not upgraded to Argon2id on verification. Impact limited by secret expiration.

#### L-8: Non-Atomic Domain Index Update

**File:** `lib/onetime/models/custom_domain.rb:173-224`
**Status:** Multi-step index swap can orphan domains on crash.

#### L-9: Missing Model-Level TTL Validation

**File:** `lib/onetime/models/receipt.rb:271-312`
**Status:** `spawn_pair` accepts arbitrary lifespan; bounds enforcement is API-layer only.

#### L-10: CSRF Token in All Response Headers

**File:** `lib/onetime/middleware/csrf_response_header.rb:30-37`
**Status:** X-CSRF-Token header on every response increases leakage surface.

---

### INFORMATIONAL

---

#### I-1: Residual Timing Side-Channel in Password Reset

**File:** `apps/api/account/logic/authentication/reset_password_request.rb:46`
**Status:** Acknowledged in code comments. Same response returned but timing may differ.

#### I-2: Default RabbitMQ `guest:guest` in Development Config

**File:** `etc/defaults/config.defaults.yaml:791`
**Status:** Development default only, not production.

#### I-3: PII Query Parameter Guard Dev-Only

**File:** `src/router/index.ts:149-151`
**Status:** PII-in-URL warnings only active in development builds.

#### I-4: Lite Dockerfile Runs as Root

**File:** `docker/variants/lite.dockerfile:110-112`
**Status:** Labeled "not for production."

#### I-5: Rodauth Default Lockout Threshold of 100

**File:** `rodauth: lib/rodauth/features/lockout.rb:33`
**Status:** Library default; onetimesecret overrides to 5 in its configuration.

#### I-6: Recovery Codes with 64-bit Entropy

**File:** `apps/web/auth/config/features/mfa.rb:68-76`
**Status:** Documented trade-off. 7-attempt lockout mitigates brute force.

---

## Risk Register

| ID   | Finding                                     | Severity | Exploitability | Business Impact                                              | Priority |
| ---- | ------------------------------------------- | -------- | -------------- | ------------------------------------------------------------ | -------- |
| H-1  | CSRF bypass on session-auth API routes      | High     | Medium         | Secret creation/account modification under victim's identity | P1       |
| H-2  | Redis exposed without auth (simple compose) | High     | High           | Full data breach of secrets and credentials                  | P1       |
| H-3  | OAuth email-based account linking           | High     | Medium         | Account takeover (requires OAuth enabled)                    | P2       |
| M-1  | Security middleware disabled by default     | Medium   | High           | Missing clickjacking/HSTS/traversal protection               | P1       |
| M-2  | Sessions survive password change            | Medium   | Low            | Compromised sessions persist after credential rotation       | P2       |
| M-3  | V1 decrypts before atomic claim             | Medium   | Low            | Plaintext in memory for losing racers                        | P3       |
| M-4  | No login rate limiting (simple mode)        | Medium   | High           | Brute force password attacks                                 | P2       |
| M-5  | S6 overlay no checksum verification         | Medium   | Low            | Supply chain attack on container init                        | P2       |
| M-6  | RabbitMQ default credentials                | Medium   | Medium         | Message interception on default deployments                  | P2       |
| M-7  | Cookie `secure` flag manual config          | Medium   | Medium         | Session hijacking via HTTP downgrade                         | P2       |
| M-8  | Passphrase rate limiter targeted DoS        | Medium   | Medium         | Legitimate recipients locked out                             | P2       |
| M-9  | `checkout_url` redirect unvalidated         | Medium   | Low            | Phishing via billing response manipulation                   | P3       |
| M-10 | Colonel panel no frontend guard             | Medium   | Low            | Admin UI structure disclosure                                | P3       |
| M-11 | MFA awaiting flag unchecked                 | Medium   | Low            | Potential MFA bypass if code reads account_id                | P2       |

---

## Positive Security Findings

The following areas demonstrate strong security engineering:

1. **Atomic burn-after-reading** -- Redis Lua CAS script prevents double-reveal races (`secret_state_management.rb`)
2. **256-bit CSPRNG identifiers** -- `SecureRandom.hex(32)` for all IDs (`familia/secure_identifier.rb`)
3. **HKDF key derivation** -- Separate purpose-specific keys from a single root secret (`key_derivation.rb`)
4. **AES-256-GCM + HMAC sessions** -- Encrypted and integrity-protected session data (`session.rb`)
5. **Constant-time comparisons** -- `Rack::Utils.secure_compare` for API tokens, HMAC, passwords
6. **Anti-enumeration** -- Same response for existing/non-existing accounts; dummy customer for timing normalization
7. **XSS prevention** -- `<textarea :value>` for secret display; DOMPurify with strict allowlist for v-html
8. **No `Marshal.load`** -- JSON-only serialization throughout Familia ORM
9. **CSP with nonces** -- Per-request `SecureRandom.base64(16)` nonces for script tags
10. **Input sanitization** -- Multi-pass decode loop, strict identifier allowlist, email normalization
11. **Role promotion CLI-only** -- No API endpoint for system role changes
12. **Colonel verification gate** -- `has_system_role?` requires email verification as defense-in-depth
13. **Docker image pinning** -- All base images pinned by SHA256 digest
14. **GitHub Actions pinning** -- Critical actions pinned by commit SHA
15. **Non-root container** -- Production image runs as `appuser` (UID 1001)

---

## Tooling Notes

- **Analysis method:** Static code review via automated agents + manual verification
- **Runtime testing:** Not performed (no production deployment per constraints)
- **Dependencies:** Gemfile.lock and pnpm-lock.yaml both present and committed; `--frozen-lockfile` enforced in Docker builds
- **No secrets found:** Verified no credentials, API keys, or secrets in committed code
- **PoC artifacts:** Reproduction steps provided inline with each finding; no external PoC scripts generated (static analysis only, no runtime environment available)

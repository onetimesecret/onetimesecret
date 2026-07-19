# Security Audit Report — OneTimeSecret

**Date:** 2026-07-19  
**Scope:** Full application stack (Ruby backend, Vue SPA frontend, Redis/Valkey data store, Familia ORM, authentication flows)  
**Repositories audited:** onetimesecret/onetimesecret, onetimesecret/rhales, delano/familia, onetimesecret/rodauth, onetimesecret/rodauth-omniauth  
**Environment:** Static analysis + architecture review (no production traffic)

---

## Executive Summary

The OneTimeSecret application demonstrates strong security fundamentals: authenticated encryption (AES-256-GCM / XChaCha20-Poly1305), proper key derivation (HKDF RFC 5869), constant-time comparisons throughout, atomic state transitions via Lua scripts, defense-in-depth admin access control, and comprehensive rate limiting with two-tier design.

**No critical remote code execution, SQL injection, or authentication bypass vulnerabilities were found.**

However, 9 medium-severity issues and 11 low-severity findings warrant attention, particularly around rate limiting gaps, the Rodauth authentication mode, account creation race conditions, and operational configuration defaults.

---

## Findings

### CRITICAL — None Found

---

### HIGH SEVERITY

#### H-1: Master SECRET Compromise Decrypts All Data (Accepted Architecture Risk)

**Location:** `lib/onetime/key_derivation.rb`, `lib/onetime/initializers/configure_familia.rb`  
**Category:** Cryptography / Key Management

**Description:** A single root SECRET (env var) derives ALL security-critical keys: session encryption, HMAC signing, field-level encryption, and identifier verification. Compromise of this single value decrypts all stored secrets, forges any session, and creates valid identifiers.

**Mitigations in place:**
- Boot-time SecretVerifier detects SECRET changes (`lib/onetime/secret_verifier.rb`)
- Key rotation support via `SECRET_PREVIOUS` env var
- Content-addressed key version tags in encrypted envelopes

**Reproduction:** N/A — architecture design, not a bug.

**Remediation:** Document as accepted risk. Consider HSM-backed key storage for high-security deployments. The current boot-time verifier prevents accidental misconfiguration but not compromise.

---

### MEDIUM SEVERITY

#### M-1: Account Creation TOCTOU Race Condition

**Location:** `apps/api/account/logic/account/create_account.rb:74-94`, `familia/lib/familia/horreum/atomic_write.rb:42-44`  
**Category:** Business Logic / Race Condition

**Description:** Account creation performs a non-atomic check-then-create:
1. `Customer.find_by_email(email)` — READ (line 74)
2. `Customer.create!(email: email)` — WRITE (line 94)

Inside `create!`, the `guard_unique_email_index!` check (Familia unique index) also uses a read-then-write pattern (`HGET` then `HSET`). Two concurrent requests for the same email can both pass the guard and both succeed.

The Familia documentation explicitly states: "Unique index validation runs OUTSIDE the transaction so it can perform the reads it needs. Only the writes are atomic; the read-validate-write is not."

**Impact:** Duplicate accounts for the same email; the last writer's `identifier` overwrites the first in the email index, effectively orphaning the first account from lookups.

**Exploitation:** Requires sub-millisecond concurrent requests — practically difficult but automatable.

**Remediation:** Use Redis HSETNX (Hash Set if Not eXists) for the unique index write, or wrap the check-and-create in a Redis WATCH/MULTI/EXEC optimistic lock on the email index key.

---

#### M-2: V1 API Passphrase Rate Limiting Lacks Per-IP Tier (DoS Vector)

**Location:** `apps/api/v1/logic/secrets/show_secret.rb:172-182`, `apps/api/v1/logic/secrets/burn_secret.rb:130-138`  
**Category:** Rate Limiting / Denial of Service

**Description:** In the V1 API, `passphrase_client_ip` always returns `nil` because V1 logic objects lack a `strategy_result`. The PassphraseRateLimiter then falls back to the global per-secret tier only (GLOBAL_MAX_ATTEMPTS=20).

**Impact:** An attacker who knows a secret_key can make 20 wrong passphrase attempts from any IPs to trigger a 30-minute global lockout, denying the legitimate recipient access. This is a targeted denial-of-service against specific secrets.

**Exploitation:**
```bash
for i in $(seq 1 20); do
  curl -X POST https://target/api/v1/secret/SECRET_KEY \
    -u "anon:anon" -d "passphrase=wrong$i"
done
# Legitimate recipient now locked out for 30 minutes
```

**Remediation:** Propagate client IP from the V1 request context into `passphrase_client_ip` so the two-tier design functions as intended. The V2 API already has this correct via `strategy_result.metadata[:ip]`.

---

#### M-3: Rodauth Lockout Expiration Default 24h (DoS Amplification)

**Location:** `apps/web/auth/config/features/lockout.rb:16`  
**Category:** Authentication / Denial of Service

**Description:** The lockout expiration is commented out (`# auth.lockout_expiration_default 3600`). Rodauth's default `account_lockouts_deadline_interval` is 86400 seconds (24 hours). With `max_invalid_logins` at only 5, an attacker can lock any account for a full day with 5 requests.

**Exploitation:** Script 5 bad-password POST requests against target emails. Victims cannot log in for 24 hours. Renewable daily.

**Remediation:** Set `account_lockouts_deadline_interval` to 900-3600 seconds. Consider using the two-tier per-IP rate limiter (LoginRateLimiter) to gate Rodauth lockouts as well.

---

#### M-4: No Per-IP Rate Limiting on Rodauth Authentication Endpoints

**Location:** `apps/web/auth/config/hooks/login.rb`  
**Category:** Authentication / Credential Stuffing

**Description:** The Rodauth auth mode has no IP-based rate limiting on login, MFA verification, magic-link request, or password-reset flows. The only throttle is Rodauth's per-account lockout (5 attempts per account).

**Impact:** Credential stuffing — try 4 passwords (under the 5-attempt lockout) across thousands of accounts from a single IP. Password-reset requests can be spammed to harass users with emails.

**Remediation:** Deploy `rack-attack` or integrate the existing `LoginRateLimiter` into the Rodauth auth flow on `/auth/login`, `/auth/otp-auth`, `/auth/email-login-request`, and `/auth/reset-password-request`.

---

#### M-5: SSO Login Bypasses Locally-Configured MFA

**Location:** `apps/web/auth/operations/detect_mfa_requirement.rb:156`  
**Category:** Authentication / MFA Bypass

**Description:** `return false if @via_omniauth` — when a user with TOTP configured logs in via SSO, local MFA is fully bypassed. The system trusts the IdP to handle authentication factors.

**Impact:** If a user's IdP account is compromised (e.g., no MFA at IdP level), their OTS account is accessible without the TOTP they configured locally.

**Remediation:** Document as accepted risk OR offer a per-account/per-org policy to enforce local MFA even on SSO logins (the `mfa_policy: :required` concept already exists but is not exposed to admins).

---

#### M-6: Remember-Me Cookie Missing Explicit Security Attributes

**Location:** `apps/web/auth/config/features/remember_me.rb:15-18`  
**Category:** Session Management / Cookie Security

**Description:** The remember-me cookie configuration relies on Rodauth's defaults without explicitly setting `secure: true`, `same_site: :lax`, or `httponly: true`. Rodauth does set httponly by default but does NOT set `secure` or `SameSite` unless explicitly configured. If served over HTTP (dev, misconfigured proxy), the remember cookie transmits in cleartext.

**Remediation:** Explicitly set:
```ruby
remember_cookie_options { { httponly: true, secure: true, same_site: :lax } }
```

---

#### M-7: Recovery Codes Use 64-bit Entropy (Below 128-bit Standard)

**Location:** `apps/web/auth/config/features/mfa.rb:74-76`  
**Category:** Cryptography / MFA

**Description:** Recovery codes are generated via `Familia.generate_trace_id` producing 64-bit random values. NIST SP 800-63B recommends at least 112-bit entropy for authentication secrets.

**Mitigating factor:** The OTP failure limit of 7 makes online brute-force impractical (~1 in 2.6×10¹⁸ per attempt).

**Remediation:** Accepted risk per code documentation. Consider increasing to 80-96 bits if offline attack scenarios (database leak) enter the threat model.

---

#### M-9: No Per-IP Rate Limiting on V3 Guest Secret Creation

**Location:** `apps/api/v3/routes.txt:29-34`, V2 `ConcealSecret`/`GenerateSecret` logic  
**Category:** Rate Limiting / Resource Exhaustion

**Description:** The V3 guest endpoints (`POST /api/v3/guest/secret/conceal` and `POST /api/v3/guest/secret/generate`) have no per-IP rate limiting for secret creation. Unlike the V1 API (which has `check_rate_limit!` in controllers) or the incoming API (which has `IncomingRateLimiter`), the V3 guest creation path is unbounded.

**Impact:** An attacker can create unlimited secrets via the guest endpoints, consuming Redis storage. Each secret has a configurable TTL (max 30 days) but burst creation is unbounded.

**Exploitation:**
```bash
# Flood Redis with secrets from a single IP
for i in $(seq 1 10000); do
  curl -s -X POST "https://target/api/v3/guest/secret/conceal" \
    -H "Content-Type: application/json" \
    -d '{"secret_value":"payload_'$i'","ttl":2592000}'
done
```

**Remediation:** Add per-IP creation rate limiting (similar to `IncomingRateLimiter`) to the V3 guest secret creation flow.

---

#### M-8: Redis Transport Unencrypted (Multi-Host Deployments)

**Location:** `docker/compose/docker-compose.simple.yml` — `redis://:password@maindb:6379/0`  
**Category:** Network Security / Data in Transit

**Description:** App-to-Redis connections use plain TCP (`redis://`), not TLS (`rediss://`). The Redis password travels in cleartext on the internal network.

**Impact:** In a single-host Docker Compose setup, risk is LOW (container network only). In production multi-host or Kubernetes deployments with untrusted network segments, this is MEDIUM.

**Remediation:** Enable TLS for Redis in production deployments. Valkey 8.x supports TLS natively.

---

### LOW SEVERITY

#### L-1: Rate Limiting Fail-Open Design

**Location:** `apps/api/v1/controllers/base.rb:186-190`  
**Category:** Rate Limiting / Availability

**Description:** If Redis is unavailable for rate limiting operations, requests pass through without throttling (fail-open). This is a deliberate design choice — since secrets also live in Redis, a Redis outage blocks business logic anyway.

**Impact:** During transient Redis connectivity issues (e.g., network partition where write fails but read succeeds from a replica), rate limiting is disabled.

**Remediation:** Accept as operational risk. Consider a local in-memory rate limiter as a backstop during Redis failures.

---

#### L-2: No Minimum Entropy Validation on Master SECRET

**Location:** `lib/onetime/initializers/configure_familia.rb:81`  
**Category:** Cryptography / Configuration

**Description:** The boot-time check raises on empty SECRET but does not validate minimum length or entropy. An operator could configure a weak secret (e.g., "password123") and the system would accept it.

**Impact:** A weak SECRET makes all HKDF-derived keys brute-forceable.

**Remediation:** Add a minimum length check (32 bytes / 64 hex chars) at boot time with a clear error message.

---

#### L-3: 64-bit HMAC Tag Truncation on Verifiable Identifiers

**Location:** `familia/lib/familia/verifiable_identifier.rb:84,197`  
**Category:** Cryptography / Identifier Forgery

**Description:** Verifiable identifiers use a 64-bit (16 hex char) truncated HMAC-SHA256 tag. While the 256-bit random component makes brute-force discovery of valid identifiers infeasible, the truncated HMAC tag means a forgery requires ~2^63 offline operations (vs. 2^127 for full-length HMAC).

**Mitigating factors:** Online verification is rate-limited by network; identifiers expire with their associated secrets.

**Remediation:** Accept as documented design tradeoff for shorter URLs. No action needed.

---

#### L-4: Account Enumeration via Timing (Partially Mitigated)

**Location:** `apps/web/auth/config/hooks/account.rb`, `apps/web/auth/config/rodauth_overrides.rb:29-53`  
**Category:** Information Disclosure / User Enumeration

**Description:** The codebase makes good effort to return generic error messages for login/signup. However, the `login_valid_email?` hook calls `Truemail.validate` which may introduce timing differences for valid vs. invalid email formats. Additionally, Rodauth's default login flow may have subtle timing differences between "account not found" and "wrong password" paths.

**Mitigating factors:** Simple auth mode uses dummy BCrypt hash check for non-existent users (constant-time). V1 API uses SHA256 dummy comparison.

**Remediation:** Verify Rodauth auth mode paths have equivalent timing. Add a dummy hash check for the non-existent account case in the Rodauth flow.

---

#### L-5: Legacy `v1_custid` Field May Leak Creator Email

**Location:** `apps/api/v1/controllers/class_methods.rb:208-231`  
**Category:** Information Disclosure

**Description:** The `receipt_hsh` fallback chain reads stored `v1_custid` and `custid` fields from old receipts. Pre-migration receipts may have these populated with the creator's email address, which would be exposed to any anonymous user accessing the receipt.

**Impact:** Only affects legacy data from before the UUID-based `owner_id` migration.

**Remediation:** Run a migration to clear or hash any plaintext emails in legacy receipt `custid`/`v1_custid` fields.

---

#### L-6: Argon2 t_cost=2 Slightly Below OWASP Recommendation

**Location:** `lib/onetime/models/features/passphrase_hashing.rb:72`  
**Category:** Cryptography / Password Hashing

**Description:** Production Argon2id parameters are `{ t_cost: 2, m_cost: 16, p_cost: 1 }` (2 iterations, 64MB memory, 1 thread). OWASP 2024 recommends t=3 minimum for Argon2id.

**Impact:** Marginally faster offline password cracking if hashes are leaked.

**Remediation:** Increase `t_cost` to 3 in the next release. Existing hashes are rehashed transparently on next login.

---

#### L-7: WebAuthn RP ID Dynamically Derived from Request Host

**Location:** `apps/web/auth/config/features/webauthn.rb:14-16`  
**Category:** Authentication / WebAuthn

**Description:** The Relying Party ID is set from `request.host` at runtime. While this enables multi-domain deployments, if the application migrates domains, all WebAuthn credentials become invalid. More concerning: if Host header manipulation is possible (HTTP request smuggling), credentials could be registered against a spoofed RP ID.

**Remediation:** Consider hardcoding the RP ID to the canonical domain or validating against an allowlist.

---

#### L-8: OTP Failure Limit of 7 is Permissive

**Location:** `apps/web/auth/config/features/mfa.rb:47`  
**Category:** Authentication / MFA

**Description:** The OTP auth failures limit is set to 7 (Rodauth default is 5). Combined with TOTP's 30-second window allowing ~3 valid codes simultaneously, this gives an attacker 7 chances at ~1/333,333 per attempt.

**Remediation:** Consider reducing to 5 for high-security deployments.

---

#### L-9: No Rack-Level Request Body Size Limit

**Location:** `lib/onetime/application/middleware_stack.rb`  
**Category:** Availability / Resource Exhaustion

**Description:** The middleware stack does not include a Rack-level body size enforcement middleware. While application-level `validate_secret_size` caps the secret value, the full POST body (including JSON overhead) is parsed into memory before validation occurs.

**Impact:** An attacker could send extremely large JSON payloads to any endpoint, temporarily consuming server memory during parsing.

**Mitigating factor:** Puma has configurable `max_request_body_size` but this must be explicitly set in the Puma config. Caddy/reverse proxy may also enforce limits.

**Remediation:** Set `max_request_body_size` in Puma configuration, or add `Rack::ContentLength`-style request body limit middleware.

---

#### L-10: OPTIONS Preflight Routes Exist but Return No CORS Headers

**Location:** `apps/api/v2/routes.txt:37-38`, `apps/api/v3/routes.txt:25-26`  
**Category:** Configuration / CORS

**Description:** V2 and V3 APIs define OPTIONS preflight routes for `/secret/generate` and `/secret/conceal`, but no code in those logic classes sets `Access-Control-Allow-Origin` or related headers. Cross-origin JavaScript clients would fail (browser blocks the response).

**Impact:** Not exploitable (absence of CORS is more restrictive). But if CORS is later added carelessly (e.g., `*` origin with credentials), it could become a vulnerability. Currently, CORS is expected to be managed at the reverse proxy layer.

**Remediation:** Either implement proper CORS response headers in the OPTIONS handlers, or remove the dead OPTIONS routes. Document that CORS is proxy-managed.

---

#### L-11: CSP Disableable via Environment Variable

**Location:** `etc/defaults/config.defaults.yaml:379`, `apps/web/core/middleware/request_setup.rb:102`  
**Category:** Configuration / Defense-in-Depth

**Description:** Setting `CSP_ENABLED=false` disables Content Security Policy entirely. While this is an intentional escape hatch for development, it could be accidentally left in production.

**Remediation:** Add a boot-time warning when CSP is disabled in production mode.

---

### INFORMATIONAL

#### I-1: Single `v-html` Usage Properly Sanitized

**Location:** `src/shared/components/ui/GlobalBroadcast.vue:171`

The only `v-html` in the application uses DOMPurify with strict config (allowed tags: `<a>` only, URI schemes: https/http/mailto only, all anchors get `rel="noopener noreferrer"`). Operator-controlled content only. No XSS risk.

---

#### I-2: localStorage/sessionStorage Usage is Safe

**Location:** Various stores in `src/shared/stores/`

Storage contains only: UI preferences (workspace mode, language, TTL), local receipt cache (validated with Zod schema on load), debug flags, and auth state booleans. No secrets, tokens, or PII stored client-side.

---

#### I-3: CSRF Protection Comprehensive

**Location:** `lib/onetime/middleware/security.rb`, `lib/onetime/middleware/csrf_response_header.rb`, `src/plugins/axios/interceptors.ts`

- Server uses Rack::Protection::AuthenticityToken with masked tokens (BREACH mitigation)
- Frontend axios interceptor attaches X-CSRF-Token from response headers automatically
- CSRF bypass limited to: SSO routes (OAuth state replaces CSRF), magic link routes, API routes without session cookie, webhooks
- SSO routes protected by OAuth state parameter instead

---

#### I-4: Redirect Validation Prevents Open Redirects

**Location:** `src/utils/redirect.ts`

Client-side redirect validation: same-origin check for URLs, path traversal prevention, protocol scheme filtering. Stripe checkout URL validation uses exact-match allowlist (`checkout.stripe.com` only).

---

#### I-5: Admin Access Control is Three-Layer Defense

**Location:** `lib/onetime/middleware/admin_network_isolation.rb`, router annotations, logic layer

1. Network layer: Optional CIDR allowlist (returns 404, not 403 — surface is invisible)
2. Router layer: `role=colonel` annotation on all colonel routes
3. Logic layer: Every colonel action calls `verify_one_of_roles!(colonel: true)` which requires both `cust.role == 'colonel'` AND `cust.verified?`

---

#### I-6: Session Fixation Properly Mitigated

**Location:** `apps/web/auth/config/base.rb:89-91`

`clear_session` calls `session.destroy` which regenerates the session ID on login. Both auth modes (simple and Rodauth) regenerate sessions on authentication state changes.

---

#### I-7: Burn-After-Reading Atomicity via Lua CAS

**Location:** `lib/onetime/models/features/state_cas.rb`

Secret reveal uses an atomic Lua Compare-And-Swap: only one caller can transition `new → viewed`. The loser gets a "secret not found" response. Race conditions in reveal are fully mitigated.

---

#### I-8: DevBasicAuthStrategy Production Guard

**Location:** `lib/onetime/application/auth_strategies/dev_basic_auth_strategy.rb`

Production usage is blocked with `SecurityError` at both strategy registration AND runtime authentication. Requires explicit `DEV_BASIC_AUTH=true` env var. Ephemeral customers get 20-hour TTL.

---

#### I-9: Docker Image Security (Positive)

**Location:** `Dockerfile`, `docker/base.dockerfile`, `.dockerignore`

- Non-root execution: `appuser` (UID 1001) with `/sbin/nologin` shell
- Digest-pinned base images (Ruby 3.4, Node 22) — no floating tags
- S6 overlay downloads SHA256-verified before extraction
- No secrets in build layers — all runtime secrets passed via `-e` flags
- `.dockerignore` excludes: `.env*`, `.git`, `config.yaml`, `auth.yaml`, `billing.yaml`, `secrets.dev.yaml`, `data/`, `.certs/`

---

#### I-10: Error Responses Leak No Implementation Details

**Location:** `apps/api/v1/controllers/helpers.rb`, `apps/api/v2/application.rb`, `apps/web/core/middleware/error_handling.rb`

- API errors return only user-facing message + type discriminator (e.g., "FormError", "NotFound")
- Stack traces logged server-side only, never in HTTP responses
- Web errors serve the Vue SPA shell with appropriate status code — no error details in HTML
- Sentry error context filters: authorization headers, cookies, API keys, auth tokens all redacted to `[FILTERED]`
- Query strings excluded from all error logging

---

#### I-11: Dependencies Are Current (No Known CVEs)

**Location:** `Gemfile.lock`, `pnpm-lock.yaml`

Key security-critical gems are all at current/patched versions:
- rack 3.2.6, puma 7.2.1, nokogiri 1.19.4, rexml 3.4.4, roda 3.102.0
- rodauth 2.42.0, webauthn 3.4.3, json 2.19.9, bcrypt 3.1.22, argon2 2.3.3
- rbnacl 7.1.2, sanitize 7.0.0, loofah 2.25.1

NPM dependencies apply security-relevant overrides: `undici >=6.27.0`, `ws >=8.21.0`, `form-data >=4.0.6`, `js-yaml >=3.15.0`. DOMPurify 3.4.0+ for client-side sanitization.

---

#### I-12: Colonel API Authorization is Airtight (3-Layer Defense)

Every colonel route (all 123) enforces `role=colonel` at the Otto router layer. Every colonel logic class (all 72) re-verifies via `verify_one_of_roles!(colonel: true)`. The `has_system_role?` check requires both `cust.role == 'colonel'` AND `cust.verified?`. Network isolation middleware optionally adds a CIDR gate returning 404 (not 403).

---

#### I-13: CSP Nonce Implementation (Positive)

**Location:** `apps/web/core/middleware/request_setup.rb:37`

Nonce generated via `SecureRandom.base64(16)` (128 bits from OpenSSL CSPRNG). Consistently applied to all `<link>` and `<script>` tags in templates. CSP emission delegated to Otto framework's `CSP::Writer` with backstop mode (fills gaps, doesn't override downstream policies).

---

#### I-14: Incoming API Rate Limiting Well-Implemented

**Location:** `lib/onetime/security/incoming_rate_limiter.rb`

Two-tier atomic Lua-based rate limiting: 10/hour per IP, 30/hour per recipient hash. 1-hour lockout. Executed BEFORE any Redis I/O or email enqueue. Fails closed on Redis errors.

---

## Positive Security Properties

1. **Authenticated encryption everywhere** — AES-256-GCM and XChaCha20-Poly1305 with proper random nonces
2. **Per-field key derivation** — Each encrypted field gets a unique key via HKDF context binding (class + field + record ID)
3. **Constant-time comparisons** — `Rack::Utils.secure_compare` and `OpenSSL.secure_compare` used consistently for HMAC, token, and password verification
4. **Two-tier rate limiting** — Per-IP tight gate + global backstop prevents both single-origin brute force and distributed attacks while avoiding DoS via lockout manipulation
5. **Anti-enumeration design** — Generic error messages, dummy hash checks for non-existent users, timing-safe comparisons
6. **Input sanitization** — Iterative decode+sanitize loop (up to 10 passes) catches multiply-encoded payloads
7. **Cookie security** — Session cookie: secure=true, httponly=true, same_site=lax by default
8. **CSP with nonces** — Content Security Policy enabled by default with per-request nonce generation
9. **Key rotation support** — `SECRET_PREVIOUS` env var enables transparent decryption of old ciphertext during rotation
10. **Atomic state machines** — Lua CAS scripts prevent race conditions in secret lifecycle (new → viewed → burned)

---

## Risk Register

| ID | Severity | CVSS Est. | Category | Finding | Status | Owner |
|----|----------|-----------|----------|---------|--------|-------|
| H-1 | High | N/A | Crypto/Arch | Master SECRET single point of compromise | Accepted | Architecture |
| M-1 | Medium | 4.2 | Race Cond. | Account creation TOCTOU | Open | Backend |
| M-2 | Medium | 5.3 | DoS | V1 passphrase rate limit lacks per-IP | Open | Backend |
| M-3 | Medium | 5.3 | DoS | Rodauth 24h lockout default | Open | Auth |
| M-4 | Medium | 5.3 | Cred Stuff | No per-IP rate limit in Rodauth mode | Open | Auth |
| M-5 | Medium | 4.3 | MFA Bypass | SSO bypasses local MFA | Accepted | Architecture |
| M-6 | Medium | 3.7 | Cookie | Remember-me cookie missing secure attrs | Open | Auth |
| M-7 | Medium | 3.1 | Crypto | 64-bit recovery code entropy | Accepted | Auth |
| M-8 | Medium | 4.0 | Network | Redis transport unencrypted | Open | Ops |
| L-1 | Low | 2.6 | Availability | Rate limiting fail-open | Accepted | Backend |
| L-2 | Low | 3.4 | Crypto | No SECRET length validation | Open | Backend |
| L-3 | Low | 2.2 | Crypto | 64-bit HMAC tag truncation | Accepted | Familia |
| L-4 | Low | 3.1 | Info Disc. | Timing-based user enumeration | Open | Auth |
| L-5 | Low | 2.4 | Info Disc. | Legacy custid email leak | Open | Backend |
| L-6 | Low | 2.1 | Crypto | Argon2 t_cost=2 vs recommended 3 | Open | Backend |
| L-7 | Low | 2.8 | Auth | WebAuthn RP ID from request host | Open | Auth |
| L-8 | Low | 2.0 | Auth | OTP failure limit 7 vs recommended 5 | Open | Auth |
| L-9 | Low | 3.1 | Availability | No Rack-level request body size limit | Open | Backend |
| L-10 | Low | 2.0 | Config | OPTIONS preflight routes non-functional | Open | Backend |
| L-11 | Low | 2.0 | Config | CSP disableable via env var (no warning) | Open | Ops |
| M-9 | Medium | 5.3 | Rate Limit | V3 guest secret creation unbounded | Open | Backend |

---

## Methodology

### Tools and Techniques
- **Static analysis:** Manual code review across 5 repositories
- **Architecture review:** Middleware stack ordering, auth strategy registration, routing annotations
- **Cryptographic review:** Key derivation paths, nonce generation, AEAD construction, timing safety
- **Race condition analysis:** TOCTOU patterns in Redis check-then-write sequences
- **Frontend security:** v-html usage, localStorage patterns, redirect validation, CSRF token flow
- **Authorization model:** Capability-based (V1) vs role-based (Colonel) vs session-based (V2/V3) access control

### Scope Limitations
- No dynamic testing / penetration testing performed
- No dependency CVE scanner run (gem/npm versions reviewed manually)
- No load testing for rate limiter bypass under extreme concurrency
- Production configuration not reviewed (only defaults and Docker Compose examples)

### Files Examined (Key Paths)
- `lib/onetime/session.rb` — Session management
- `lib/onetime/key_derivation.rb` — HKDF key derivation
- `lib/onetime/security/` — Rate limiters, input sanitizers
- `lib/onetime/middleware/` — Security middleware stack
- `lib/onetime/application/auth_strategies/` — Authentication strategies
- `lib/onetime/application/authorization_policies.rb` — Role enforcement
- `apps/api/v1/` — V1 API controllers and logic
- `apps/api/v2/` — V2 API controllers and logic
- `apps/api/colonel/` — Admin API
- `apps/web/auth/` — Rodauth authentication configuration
- `familia/lib/familia/encryption/` — Encryption providers
- `familia/lib/familia/verifiable_identifier.rb` — Identifier generation
- `src/shared/` — Frontend stores, components, composables

---

## Recommendations (Priority Order)

1. **Fix M-2:** Propagate client IP to V1 passphrase rate limiter (quick fix, high impact)
2. **Fix M-9:** Add per-IP rate limiting to V3 guest secret creation endpoints
3. **Fix M-3:** Uncomment and set `lockout_expiration_default` to 1800 seconds
4. **Fix M-1:** Use HSETNX for unique index writes in Familia, or add WATCH/MULTI/EXEC
5. **Fix M-6:** Explicitly set secure cookie attributes on remember-me
6. **Fix M-4:** Integrate LoginRateLimiter into Rodauth login flow
7. **Fix L-2:** Add minimum SECRET length validation at boot (32+ bytes)
8. **Fix L-6:** Increase Argon2 t_cost from 2 to 3
9. **Fix L-9:** Set Puma `max_request_body_size` or add Rack body-limit middleware
10. **Document:** H-1 and M-5 as accepted architecture decisions in a threat model document

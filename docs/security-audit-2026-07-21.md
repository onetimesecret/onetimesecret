# Security Audit Report: OneTimeSecret

**Date:** 2026-07-21
**Scope:** Full application security analysis across 6 repositories
**Auditor:** Automated security analysis (Claude Code)
**Prior Audit:** 2026-07-12 (referenced for delta analysis)

## Repositories Examined

| Repository | Branch | Commit |
|------------|--------|--------|
| onetimesecret/onetimesecret | main | `9b768694d7205a7a6b0e89810b4274a8b1b63da3` |
| onetimesecret/rhales | main | `ca79eaf251436ef9dcab4581113fcd4d8fd39fda` |
| delano/otto | main | `7e1f4ef3519e5dd7ae991f9f542b76cf6715ea2f` |
| delano/familia | main | `df9992b57dd39e814bfd5f2fb77a220ad6c90bf1` |
| onetimesecret/rodauth | main | `2732c44d1095f47ba552666a38adf87bd8c4732e` |
| onetimesecret/rodauth-omniauth | main | `9fe8152732f7f5409e392239411bd47fc6bf6e0a` |

---

## Executive Summary

This is a follow-up audit to the 2026-07-12 assessment. Since that report, significant security improvements have been implemented -- notably the two-tier login rate limiter (addressing M-2 from the prior audit), credential watermarking for session revocation, and the retirement of the v1 unsalted-SHA-256 encryption key fallback.

This audit goes deeper into authentication token lifecycle, API authentication, account enumeration, and data-layer security. The core secret-sharing product remains well-engineered: atomic burn-after-reading via Lua CAS, AES-256-GCM encryption at rest with HKDF key derivation, and proper session encryption with HMAC verification are all correctly implemented.

The findings below are concentrated in three areas: (1) the API authentication path lacks parity with the session authentication path on rate limiting and token storage, (2) Rodauth token storage patterns store raw tokens in the database (an upstream architectural choice), and (3) several legacy code paths have weaker security properties than their modern replacements.

**Finding Distribution:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 5 |
| Medium | 11 |
| Low | 11 |

---

## Findings

### HIGH Severity

#### H-1: API Tokens Stored in Plaintext in Redis

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:19,67-69`
**Category:** Credential Storage
**CWE:** CWE-256 (Plaintext Storage of a Password)

API tokens (apitokens) are stored as plaintext strings in Redis hash fields on the Customer model. The `regenerate_apitoken` method generates a token via `Familia.generate_id` and stores it directly. Unlike passwords (hashed with Argon2id), API tokens are not hashed before storage. A Redis data breach would expose all API tokens immediately, granting full API access to every account.

**Affected code:**
```ruby
# deprecated_fields.rb:19
base.field :apitoken

# deprecated_fields.rb:67-69
def regenerate_apitoken
  apitoken! Familia.generate_id
  apitoken
end
```

**Remediation:** Store a SHA-256 (or bcrypt) hash of the token; compare using the hash. Only show the raw token once at generation time. This is a breaking change requiring token regeneration for all users.

---

#### H-2: No Rate Limiting on API Basic Auth Endpoints

**File:** `lib/onetime/application/auth_strategies/basic_auth_strategy.rb` (entire file)
**Category:** Authentication / Brute Force
**CWE:** CWE-307 (Improper Restriction of Excessive Authentication Attempts)
**Delta from prior audit:** The 2026-07-12 audit flagged M-2 (no per-IP login rate limiting). Since then, `LoginRateLimiter` was added for session-based login. However, the API Basic Auth path was not covered by this fix.

The `BasicAuthStrategy` has zero rate limiting. No call to any rate limiter exists within `authenticate()`. An attacker with a valid username can brute-force API keys via HTTP Basic Auth with no throttling. The only mitigation is the manual IP ban middleware (`IPBan`), which requires human intervention.

**Remediation:** Port the two-tier design from `LoginRateLimiter` to the Basic Auth path. Key on username+IP and username globally. This is the highest-priority remediation item.

---

#### H-3: No Session Revocation in Legacy Password Reset Path

**File:** `apps/api/account/logic/authentication/reset_password.rb:33-91`
**Category:** Session Management
**CWE:** CWE-613 (Insufficient Session Expiration)

The legacy `ResetPassword.process` method updates the passphrase and destroys the reset secret but performs NO session revocation -- no credential watermark stamping, no Redis session blob deletion, no `RevokeAllForCustomerExceptCurrent` call. If an attacker has a valid session, it survives the password reset.

This contrasts sharply with the Rodauth-based reset path (`apps/web/auth/config/hooks/account.rb:445-621`), which implements five-layer session revocation including credential watermarking, SQL session cleanup, Redis blob revocation, and async sweep backup.

**Severity note:** If the application routes all production password resets through Rodauth (full auth mode), this finding's effective severity drops to Medium. In simple auth mode, this is the only password reset path and the severity is High.

**Remediation:** Add session revocation to the legacy path, or ensure simple-mode deployments cannot use this path without revocation.

---

#### H-4: Rodauth Auth Tokens Stored as Plaintext in Database

**Files:** `rodauth/lib/rodauth/features/email_auth.rb:228-232`, `rodauth/lib/rodauth/features/reset_password.rb:288-303`, `rodauth/lib/rodauth/features/verify_account.rb:288-303`
**Category:** Credential Storage
**CWE:** CWE-256 (Plaintext Storage of a Password)

All Rodauth token types (magic link, password reset, email verification) store the raw `SecureRandom.urlsafe_base64(32)` token in the database. The HMAC transformation (`convert_email_token_key`) happens only at the URL layer, not at rest.

**Mitigating factors:**
- When `hmac_secret` (AUTH_SECRET) is configured, the URL token is an HMAC of the stored key -- a database-only breach does not yield usable tokens
- OTS enforces `hmac_secret_guard` requiring AUTH_SECRET at boot
- Token entropy is 256 bits (not brute-forceable)

**Residual risk:** If an attacker obtains both the database and AUTH_SECRET, tokens are directly computable. Best practice (as implemented by Devise) is to store only a hash of the token.

**Remediation:** This is an upstream Rodauth architectural choice. Consider contributing a token-hashing feature upstream or implementing a local monkey-patch that hashes tokens before storage.

---

#### H-5: No Rate Limiting on Magic Link Token Verification

**File:** `rodauth/lib/rodauth/features/email_auth.rb:91-101`
**Category:** Authentication / Brute Force
**CWE:** CWE-307 (Improper Restriction of Excessive Authentication Attempts)

The email auth POST route simply checks the token and returns success or error with no tracking of failed attempts. While 256-bit token entropy makes brute force computationally infeasible, the absence of rate limiting means no alerting on suspicious verification attempts and no defense-in-depth if token entropy is ever reduced.

**Remediation:** Add per-account rate limiting on token verification attempts at the application layer (e.g., via middleware or a Rodauth hook).

---

### MEDIUM Severity

#### M-1: Session Login Timing Side-Channel

**File:** `apps/web/core/logic/authentication/authenticate_session.rb:37-42`
**Category:** Account Enumeration
**CWE:** CWE-208 (Observable Timing Discrepancy)

When an account does not exist, `find_by_email` returns nil and the method returns immediately, skipping the Argon2 password verification (~100-300ms). For an existing account, the hash comparison adds measurable latency. This timing difference is network-measurable.

The application already has `Customer.dummy` with a pre-computed Argon2 hash for exactly this purpose -- it is used in `BasicAuthStrategy` (line 54) but NOT in the session-based `AuthenticateSession` login flow.

**Remediation:** Insert `Customer.dummy.passphrase?(@passwd)` when `potential` is nil to equalize timing.

---

#### M-2: No Expiry on Email Verification Tokens

**File:** `rodauth/lib/rodauth/features/verify_account.rb` (absence of deadline)
**Category:** Token Lifecycle
**CWE:** CWE-613 (Insufficient Session Expiration)

Unlike reset_password (24h), verify_login_change (24h), and email_auth (15min in OTS), the verify_account feature has no deadline column and no expiry mechanism. Verification tokens never expire. A token generated today remains valid indefinitely.

The `account_verification_keys` migration confirms: `requested_at` and `email_last_sent` columns exist but no `deadline` column, unlike `account_login_change_keys` which has `DateTime :deadline`.

**Remediation:** Add a deadline column to `account_verification_keys` and configure `verify_account_deadline_interval` in Rodauth.

---

#### M-3: AUTH_SECRET/ACCOUNT_ID_SECRET Enforcement Gap

**Files:** `apps/web/auth/config/base.rb:11-12,26-27`
**Category:** Configuration Security
**CWE:** CWE-636 (Not Failing Securely)

The `hmac_secret_guard` and `account_id_obfuscation` features are referenced in configuration but their implementing gem is not present on this system. If these features are not installed, the boot-time enforcement of AUTH_SECRET and ACCOUNT_ID_SECRET may not be active. Without AUTH_SECRET, tokens travel in plaintext URLs. Without ACCOUNT_ID_SECRET, sequential integer account IDs are exposed in token URLs.

The `.env.reference` file shows `AUTH_SECRET` is commented out, meaning new deployments could easily omit it.

**Remediation:** Ensure the gem providing these features is in the Gemfile, or add application-level boot checks that refuse to start without these secrets.

---

#### M-4: Magic Link Resend Cooldown Too Short (30 seconds)

**File:** `apps/web/auth/config/features/email_auth.rb:20`
**Category:** Abuse Prevention
**CWE:** CWE-799 (Improper Control of Interaction Frequency)

OTS reduces the Rodauth default resend cooldown from 300 seconds to 30 seconds. This allows up to 120 magic link emails per hour per account. The rate limit is per-account only -- no global or per-IP rate limit exists at the Rodauth level.

**Remediation:** Increase to at least 60 seconds, and add per-IP rate limiting for magic link requests.

---

#### M-5: Legacy Password Reset Has No Rate Limiting

**File:** `apps/api/account/logic/authentication/reset_password_request.rb` (entire file)
**Category:** Abuse Prevention
**CWE:** CWE-799 (Improper Control of Interaction Frequency)

The legacy `ResetPasswordRequest` class has no rate limiting on how frequently reset emails can be requested. Unlike the Rodauth path (300-second cooldown) or the email change flow (`MAX_REQUESTS = 5` per 24h), this endpoint has no throttle.

**Remediation:** Add per-email rate limiting matching the Rodauth path's 5-minute cooldown.

---

#### M-6: Insecure apitoken? in Deprecated Module (Dead Code)

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:63`
**Category:** Code Quality / Timing Attack
**CWE:** CWE-208 (Observable Timing Discrepancy)

An insecure `apitoken?` implementation using plain `==` comparison exists in the deprecated module, alongside the secure version using `Rack::Utils.secure_compare` on the Customer class directly (line 268). Ruby's method resolution order means the secure version takes priority, but the insecure version remains as dead code that could be called if method resolution changes.

**Remediation:** Delete the method from `deprecated_fields.rb` or replace its body with the secure `Rack::Utils.secure_compare` version.

---

#### M-7: Plaintext Email Addresses in Redis Key Names

**File:** `lib/onetime/security/login_rate_limiter.rb:230-238`
**Category:** Information Disclosure
**CWE:** CWE-200 (Exposure of Sensitive Information)

Login rate limiter keys are constructed as `login:attempts:#{email}` and `login:locked:#{email}:#{ip}`. Anyone with Redis read access can enumerate every email that has had a failed login attempt via SCAN. The code obscures emails in log output (`OT::Utils.obscure_email`) but stores them in plaintext in Redis key names. The incoming rate limiter correctly uses hashed recipients (`incoming:attempts:rcpt:#{hash}`), showing this pattern was considered elsewhere.

**Remediation:** Hash the email before embedding it in the key name (e.g., `login:attempts:#{Digest::SHA256.hexdigest(email)}`).

---

#### M-8: No Redis TLS

**Category:** Data in Transit
**CWE:** CWE-319 (Cleartext Transmission of Sensitive Information)
**Delta from prior audit:** Previously flagged as L-8 in the 2026-07-12 report.

All Redis connections use plaintext `redis://`. No `rediss://` usage, no `ssl_params`, no `verify_mode` options. Data in transit between the application and Redis (secrets, session data, customer records) is unencrypted. This was already noted in the prior audit; severity upgraded to Medium given the sensitivity of data stored.

**Remediation:** Document and support `rediss://` connection URIs. For Docker deployments, configure Stunnel or a TLS proxy sidecar.

---

#### M-9: Legacy Minimum Password Length (6 Characters)

**File:** `apps/api/account/logic/authentication/reset_password.rb:30`
**Category:** Authentication
**CWE:** CWE-521 (Weak Password Requirements)

The legacy password reset path enforces a minimum password length of only 6 characters, below NIST SP 800-63B's recommendation of 8+. The Rodauth path uses configurable `login_password_requirements_base` which is typically stricter.

**Remediation:** Raise the minimum to 8 characters to match NIST recommendations.

---

#### M-10: Invite Signup Leaks Account Existence

**File:** `apps/api/invite/logic/invites/signup_and_accept.rb:80-96`
**Category:** Account Enumeration
**CWE:** CWE-204 (Observable Response Discrepancy)

The invite signup flow explicitly returns "An account with this email already exists" when a duplicate is detected.

**Mitigating factors:**
- The email is derived from the invitation token, not user-supplied
- A valid invitation token is required to reach this endpoint
- `InviteTokenRateLimiter` is enforced

**Remediation:** Return a generic message and redirect to login, consistent with the enumeration-safe patterns used elsewhere.

---

#### M-11: Password-Reset Timing Channel

**File:** `apps/api/account/logic/authentication/reset_password_request.rb:44-46`
**Category:** Account Enumeration
**CWE:** CWE-208 (Observable Timing Discrepancy)

The code explicitly acknowledges that timing differences between existing and non-existing accounts are a residual information leak. The logical response is identical, but execution paths differ in duration (nonexistent accounts return immediately; existing accounts perform secret creation + email sending).

**Remediation:** Add a dummy hash operation or calibrated sleep for nonexistent accounts to equalize timing.

---

### LOW Severity

#### L-1: Magic Link Token Reuse Across Requests

**File:** `rodauth/lib/rodauth/features/email_auth.rb:104-115`

When a user requests a new magic link while an unexpired one exists, the same token is reused (not regenerated). An older magic link email remains valid alongside the newer one.

---

#### L-2: Token Consumed Before Password Change in Legacy Reset

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:89-96`

The `valid_reset_secret!` method deletes the secret at validation time, BEFORE the password is actually changed. If `update_passphrase` fails, the token is consumed but the password was not changed.

---

#### L-3: API Token Generation Entropy Unclear

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:68`

API tokens are generated via `Familia.generate_id`. Without visibility into the implementation, it is unclear whether it uses a CSPRNG with sufficient entropy (128+ bits).

---

#### L-4: DNS Widget Uses Unsanitized innerHTML

**File:** `src/assets/approximated/dnswidget.v1.js:24,53,131,134,148,152`

The third-party DNS widget uses `innerHTML` and `insertAdjacentHTML` with API responses without sanitization. Acceptable if the API is trusted, but bypasses the otherwise clean sanitization practices.

---

#### L-5: No SRI on Static Assets

Assets are self-hosted (bundled by Vite, served from `/dist`) without Subresource Integrity attributes. Mitigated by same-origin hosting and nonce-based CSP.

---

#### L-6: GitHub Actions Pin by Tag

**File:** `.github/workflows/*.yml`

`actions/setup-python@v5` is pinned by tag rather than SHA. All other actions and Docker images are properly SHA-pinned.

---

#### L-7: Passphrase Rate Limiter Keys Expose Secret IDs

**File:** `lib/onetime/security/passphrase_rate_limiter.rb:223-231`

Keys constructed as `passphrase:attempts:#{secret_id}` reveal which secrets have had passphrase attempts against them.

---

#### L-8: No Redis ACL Configuration

No Redis ACL rules are configured. Application connections have full command access including dangerous commands like FLUSHALL and CONFIG SET.

---

#### L-9: Recovery Codes Stored Unhashed

**File:** `apps/web/auth/migrations/001_initial.rb:196,200-207`

Recovery codes and SMS codes are stored as plaintext strings in the auth database. Standard Rodauth behavior but hashing would provide defense-in-depth.

---

#### L-10: Login Rate Limiters Allow Bounded Burst Overshoot

Login/passphrase rate limiters split check and record into separate operations (pipelined read + Lua write). This allows a bounded burst overshoot under high concurrency. Documented as an accepted trade-off.

---

#### L-11: Dynamic Link Element Without CSP Nonce

**File:** `src/shared/composables/useMarkdownTheme.ts:19-25`

Creates a `<link>` element for highlight.js CSS themes without a nonce attribute. Could be blocked by CSP if style-src requires nonces.

---

## Positive Security Findings

The following security controls are well-implemented and deserve recognition:

### Cryptography and Key Management
- **HKDF key derivation** from single root secret with purpose separation (session, identifier, familia-enc, key-verifier)
- **AES-256-GCM** session encryption with random IV + HMAC verification (constant-time via `Rack::Utils.secure_compare`)
- **XChaCha20-Poly1305** (rbnacl/libsodium) for Familia encrypted fields with AES-256-GCM fallback
- **Argon2id** password hashing with configurable parameters and BCrypt legacy support
- **Key rotation support** via `SECRET_PREVIOUS` env var with content-addressed version tags
- **Boot-time key verifier** detects SECRET mismatch before serving requests

### Session Management
- **256-bit session IDs** (64-char hex), cryptographically random
- **Session codec** never raises, never Marshal.loads, returns nil on any failure
- **Five-layer session revocation** in Rodauth password reset (credential watermark + SQL cleanup + Redis blob deletion + async sweep + fail-secure design)
- **Credential watermarking** (`last_password_update`) with strict `<=` comparison invalidates all pre-change sessions

### Authentication
- **Timing attack mitigation** in Basic Auth via dummy customer with pre-computed Argon2 hash
- **MFA bypass protection** with explicit string-key `'awaiting_mfa'` check (not symbol)
- **Account enumeration prevention** on signup, password reset, and verification resend -- all backed by explicit CWE-204 references and comprehensive tests
- **SSO account takeover prevention** (H-3 in OmniAuth hooks): refuses to auto-link SSO identity to existing account by email

### Atomic Operations
- **Burn-after-reading** via Lua CAS script -- exactly one concurrent caller wins the reveal; losers get nil
- **Connection pinning** for WATCH/MULTI sequences prevents connection pool rotation from breaking optimistic locking
- **Atomic rate limiting** via Lua scripts for INCR + EXPIRE + lockout in a single Redis roundtrip

### Input Handling
- **Iterative decode-then-sanitize loop** (max 10 passes) handles multiply-encoded payloads
- **Strict identifier allowlist** `[a-zA-Z0-9_-]`
- **Email header injection prevention** via newline removal
- **No unsafe deserialization** in production (no Marshal.load, no YAML.load, JSON-only)
- **DOMPurify** with strict config (only `<a>` tags allowed) for the single v-html use

### Frontend SPA
- **Cookie-based sessions** (no tokens in localStorage)
- **Nonce-based CSP** with single-chunk builds
- **Open redirect prevention** with strict URL validation (rejects `://`, `..`, `./`, protocol schemes)
- **Checkout URL allowlist** (Stripe domains only, no wildcards)
- **PII scrubbing** in Sentry breadcrumbs (emails, secret paths, token params)
- **Zod schema validation** on all API responses

### Infrastructure
- **Admin network isolation** via CIDR allowlist (returns 404, not 403)
- **PostgreSQL password hash separation** via `SECURITY DEFINER` functions
- **SSRF protection** on favicon fetch (HTTPS-only, size limit, no SVG)
- **All Docker images and Actions SHA-pinned** (except one setup-python tag)
- **Test database isolation** via hard-coded port 2121 requirement

---

## Risk Register

| ID | Finding | Severity | CVSS Est. | Exploitability | Business Impact | Remediation Priority | Status |
|----|---------|----------|-----------|----------------|-----------------|---------------------|--------|
| H-1 | API tokens plaintext in Redis | High | 7.5 | Requires Redis access | Full API account takeover | P1 | Open |
| H-2 | No rate limit on API Basic Auth | High | 7.3 | Low skill, remote | Credential brute force | P1 | Open |
| H-3 | No session revocation in legacy reset | High | 7.1 | Requires valid session | Session persistence after password change | P1 (simple mode) / P2 (full mode) | Open |
| H-4 | Rodauth tokens plaintext in DB | High | 6.8 | Requires DB + secret access | Token forging for any account | P2 (upstream) | Open |
| H-5 | No rate limit on magic link verify | High | 5.3 | Low (256-bit tokens) | Defense-in-depth gap | P3 | Open |
| M-1 | Login timing side-channel | Medium | 5.3 | Requires statistical analysis | Account enumeration | P2 | Open |
| M-2 | No verify_account token expiry | Medium | 5.0 | Requires email interception | Indefinite token validity | P2 | Open |
| M-3 | AUTH_SECRET enforcement gap | Medium | 6.5 | Misconfiguration | Plaintext tokens in URLs | P1 | Open |
| M-4 | 30s magic link resend cooldown | Medium | 4.3 | Low skill, remote | Email bombing | P3 | Open |
| M-5 | No rate limit on legacy reset request | Medium | 4.3 | Low skill, remote | Email bombing | P3 | Open |
| M-6 | Insecure apitoken? dead code | Medium | 3.7 | Requires code change | Timing attack on API tokens | P3 | Open |
| M-7 | Plaintext email in Redis keys | Medium | 4.0 | Requires Redis access | Email enumeration | P2 | Open |
| M-8 | No Redis TLS | Medium | 5.7 | Requires network access | Data interception | P2 | Open |
| M-9 | 6-char minimum password (legacy) | Medium | 4.0 | Low skill | Weak passwords | P3 | Open |
| M-10 | Invite signup leaks accounts | Medium | 3.5 | Requires valid invite token | Account enumeration | P3 | Open |
| M-11 | Password-reset timing channel | Medium | 3.5 | Requires statistical analysis | Account enumeration | P3 | Open |
| L-1 | Magic link token reuse | Low | 2.0 | -- | Extended token validity | P4 | Open |
| L-2 | Token consumed before pwd change | Low | 2.5 | Race condition | User lockout from reset | P4 | Open |
| L-3 | API token entropy unclear | Low | 2.0 | -- | Weak tokens if PRNG is weak | P4 | Open |
| L-4 | DNS widget unsanitized innerHTML | Low | 3.0 | Requires API compromise | XSS via DNS widget | P4 | Open |
| L-5 | No SRI on static assets | Low | 1.5 | Requires origin compromise | Script tampering | P4 | Open |
| L-6 | GH Action pin by tag | Low | 1.0 | Supply chain | Build compromise | P4 | Open |
| L-7 | Passphrase rate limit key leaks | Low | 2.0 | Requires Redis access | Secret activity enumeration | P4 | Open |
| L-8 | No Redis ACL | Low | 3.0 | Requires Redis access | Command abuse | P4 | Open |
| L-9 | Recovery codes unhashed | Low | 2.5 | Requires DB access | Recovery code theft | P4 | Open |
| L-10 | Rate limiter burst overshoot | Low | 2.0 | High concurrency | Extra attempts before lockout | P4 | Open |
| L-11 | Link element without CSP nonce | Low | 1.0 | -- | Style injection | P4 | Open |

---

## Delta from 2026-07-12 Audit

### Resolved Since Prior Audit
- **M-2 (prior):** Per-IP login rate limiting -- now implemented via `LoginRateLimiter` with two-tier design (per-email+IP and global backstop). Session login path is covered.
- **Encryption key rotation:** `SECRET_PREVIOUS` support and v1-to-v2 migration completed. Legacy unsalted-SHA-256 fallback retired 2026-07-18.

### Persistent from Prior Audit
- **L-8 (prior) -> M-8 (current):** No Redis TLS -- upgraded from Low to Medium given sensitivity of data.
- **M-1 (prior):** Account lockout DoS -- still present (Rodauth default behavior).

### New Findings in This Audit
- H-1 through H-5, M-1 through M-11, L-1 through L-11 (27 total new findings not covered in the prior audit's scope).

---

## Recommended Remediation Priority

### Immediate (P1) -- Address within 1 sprint
1. **H-2:** Add rate limiting to BasicAuthStrategy (port LoginRateLimiter's two-tier design)
2. **H-1:** Hash API tokens before storage in Redis
3. **M-3:** Add boot-time check that refuses to start without AUTH_SECRET and ACCOUNT_ID_SECRET
4. **H-3:** Add session revocation to legacy password reset path (or deprecate it)

### Short-term (P2) -- Address within 2-4 weeks
5. **M-1:** Use Customer.dummy for timing equalization in session login
6. **M-7:** Hash emails in rate limiter Redis key names
7. **M-8:** Document and support Redis TLS connections
8. **M-2:** Add deadline column to account_verification_keys
9. **H-4:** Evaluate contributing token-hashing feature to Rodauth upstream

### Medium-term (P3) -- Address within next quarter
10. **M-6:** Remove insecure apitoken? from deprecated_fields.rb
11. **M-4:** Increase magic link resend cooldown to 60+ seconds
12. **M-5:** Add rate limiting to legacy password reset request
13. **M-9:** Raise minimum password length to 8 characters
14. **M-10/M-11:** Equalize timing on enumeration-prone paths
15. **H-5:** Add per-account rate limiting on magic link token verification

---

## Methodology

This audit employed static analysis of the complete source tree across all 6 repositories, examining:

- ~336 HTTP routes across 13 Rack-mounted applications
- Authentication strategies (session, Basic Auth, SSO, magic link, WebAuthn, TOTP)
- Session lifecycle (creation, encryption, validation, revocation)
- Redis data model (key patterns, Lua scripts, encryption at rest)
- SQL schema (Rodauth tables, migrations, database functions)
- Cryptographic primitives (HKDF, AES-256-GCM, XChaCha20-Poly1305, Argon2id)
- Rate limiting (login, passphrase, incoming, DNS, feedback, invite)
- Input sanitization and output encoding
- Frontend SPA security (CSRF, XSS sinks, token storage, CSP)
- Supply chain (Gemfile, Docker images, GitHub Actions)

Analysis was performed by 20+ specialized agents covering distinct security domains, with findings cross-referenced and verified against source code.

---

## Scope Limitations

- No dynamic testing was performed (no running application, no network-level probing)
- No penetration testing or exploit development
- No review of production deployment configuration (only default configs and `.env.reference`)
- Rodauth upstream library analysis was limited to the forked version at `onetimesecret/rodauth`
- No review of RabbitMQ security configuration
- SSRF testing was not performed against the favicon fetch endpoint

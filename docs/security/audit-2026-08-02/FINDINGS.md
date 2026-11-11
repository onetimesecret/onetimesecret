# Security Audit Report — OneTimeSecret

**Date:** 2026-08-02\
**Scope:** Full application stack (Ruby backend, Vue 3 SPA frontend, Redis/Valkey data store, Familia ORM, authentication flows, SSO, billing)\
**Repositories audited:** onetimesecret/onetimesecret, onetimesecret/rhales, delano/otto, delano/familia, onetimesecret/rodauth, onetimesecret/rodauth-omniauth\
**Environment:** Static analysis + architecture review (no production traffic)\
**Prior audits:** 2026-07-06 (all fixed), 2026-07-19 (0 confirmed), 2026-07-30 (all fixed)

---

## Executive Summary

The OneTimeSecret application maintains strong security fundamentals. The core security property — atomic one-time secret reveal via Redis Lua compare-and-set — is correctly implemented and race-condition-resistant. Encryption at rest (AES-256-GCM / XChaCha20-Poly1305 with per-field HKDF key derivation), session security (AES-256-GCM encrypted + HMAC signed cookies), and CSRF protection (nonce-based CSP, SameSite cookies, authenticity tokens) all meet or exceed industry standards.

All findings from prior audits (2026-07-06, 2026-07-19, 2026-07-30) remain resolved in the current codebase.

**No critical or high-severity vulnerabilities were found.**

This audit identified **4 medium-severity** and **8 low-severity** findings, primarily in account enumeration vectors, HTTP security header configuration, and a vendored third-party widget. The application's defense-in-depth posture is strong, with most findings representing hardening opportunities rather than exploitable vulnerabilities.

---

## Severity Summary

| Severity | Count | Impact |
|----------|-------|--------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 4 | Account enumeration (2), HTTP security headers (1), vendored widget XSS (1) |
| Low | 8 | Configuration defaults, logging, rate limiting gap, deprecated code |
| Informational | 20+ | Positive security patterns confirmed |

---

## Findings

### M-1: Login Route Account Enumeration

**Severity:** Medium\
**Component:** Authentication (Rodauth)\
**File:** `rodauth/lib/rodauth/features/login.rb:60`, `rodauth/lib/rodauth/features/base.rb:60`

**Description:** The login route returns distinct error messages for "no matching login" (email not found) and "invalid password" (email found, wrong password). This difference allows an attacker to determine whether a specific email address is registered.

**Evidence:** The login flow uses `throw_error_reason(:no_matching_login, ...)` for unknown emails and `throw_error_reason(:invalid_password, ...)` for known emails with wrong passwords. These produce different user-visible error messages.

**Exploitation scenario:** An attacker submits login requests with target email addresses at low rate (below rate limiter thresholds of 5/15min per email+IP). By observing the error message, they can build a list of registered email addresses. This list can then be used for targeted phishing, credential stuffing from other breaches, or social engineering.

**Mitigating factors:**
- Login rate limiter: 5 attempts per email+IP per 15 minutes, 30-minute lockout
- Rodauth account lockout after 5 invalid password attempts
- Password reset route is already enumeration-safe (Finding 7.1 in prior audit, confirmed fixed)

**Remediation:** Override Rodauth's login error handling to return an identical generic message (e.g., "Invalid credentials") for both "no matching login" and "invalid password" scenarios. Add constant-time dummy Argon2 verification when no account is found to prevent timing-based enumeration:

```ruby
# In Rodauth configuration:
no_matching_login_message { "Invalid credentials" }
invalid_password_message { "Invalid credentials" }

# Add timing-safe dummy verification for missing accounts:
account_from_login do |login|
  acct = super(login)
  unless acct
    # Perform dummy Argon2 hash to equalize timing
    Argon2::Password.verify_password("dummy", Argon2::Password.create("dummy"))
  end
  acct
end
```

---

### M-2: Account Registration Enumeration

**Severity:** Medium\
**Component:** Authentication (Rodauth)\
**File:** `rodauth/lib/rodauth/features/create_account.rb:101-105`

**Description:** The account creation route returns `"already an account with this login"` when a registration attempt uses an email that is already registered. This explicitly confirms email registration status.

**Evidence:** `save_account` catches uniqueness constraint violations and sets the error message via `already_an_account_with_this_login_message`.

**Exploitation scenario:** An attacker submits registration requests with target emails. The distinct error message confirms whether each email is already registered. The `CreateAccountRateLimiter` (10 attempts/IP/hour) constrains throughput but allows ~240 probes per day per IP address.

**Mitigating factors:**
- Rate limiting: 10 attempts per IP per hour
- AdminAuditEvent triggered when rate limit is hit
- Email verification required before account activation

**Remediation:** Return a generic message regardless of account existence: "If this email is available, a verification email has been sent." For already-registered emails, send a notification email ("Someone tried to create an account with your email — did you mean to sign in?") rather than revealing the state in the HTTP response.

---

### M-3: HTTP Security Headers Not Set as Response Headers

**Severity:** Medium\
**Component:** Middleware / Security Headers\
**Files:** `lib/onetime/middleware/security.rb`, `apps/web/core/templates/partials/head-base.rue:7-9`

**Description:** Three security headers are set only via HTML `<meta>` tags, not as HTTP response headers. Meta tags are weaker than HTTP headers (they can be overridden by injected content, are ignored for non-HTML resources, and are not processed by all security tools):

1. **Referrer-Policy** — set as `strict-origin-when-cross-origin` via meta tag. For a secret-sharing application where URLs contain secret identifiers, `no-referrer` would be more appropriate to prevent secret URLs from leaking in Referer headers on same-origin navigations.

2. **X-Content-Type-Options** — The `Rack::Protection::XSSHeader` middleware (which sets `X-Content-Type-Options: nosniff`) is disabled by default (`xss_header` defaults to `false` in middleware config).

3. **Permissions-Policy** — set only via meta tag, not as HTTP header.

**Evidence:**
```html
<!-- head-base.rue, lines 7-9 -->
<meta name="referrer" content="strict-origin-when-cross-origin">
<meta http-equiv="X-Content-Type-Options" content="nosniff">
<meta http-equiv="Permissions-Policy" content="...">
```

The Caddyfile example sets `Referrer-Policy "no-referrer"` at the reverse proxy layer, but this depends on operator configuration and is not enforced by the application itself.

**Remediation:**
1. Enable `MIDDLEWARE_XSS_HEADER=true` to get `X-Content-Type-Options: nosniff` as an HTTP header.
2. Add `Referrer-Policy: no-referrer` as an HTTP response header in application middleware, particularly on secret-reveal routes (`/secret/*`, `/private/*`).
3. Set `Permissions-Policy` as an HTTP response header.

---

### M-4: Vendored DNS Widget Injects Unsanitized HTML

**Severity:** Medium\
**Component:** Frontend (third-party widget)\
**File:** `src/assets/approximated/dnswidget.v1.js:148,152`

**Description:** The Approximated DNS widget receives HTML from its external API and injects it into the DOM using `insertAdjacentHTML('beforeend', ...)` without any sanitization.

**Evidence:**
```javascript
// Line 148
widget.insertAdjacentHTML('beforeend', inst.html);
// Line 152
widget.insertAdjacentHTML('beforeend', data.verify_section.html);
// Line 155 — CSS selector injection
document.querySelector("[data-apxid='"+dataApxId+"']")...
```

**Exploitation scenario:** If the Approximated API is compromised or returns attacker-controlled HTML, XSS is possible within the custom-domain management UI. The `dataApxId` parameter could also break out of the CSS attribute selector if it contains `']`.

**Mitigating factors:**
- Only admin/workspace users with custom domains interact with this widget
- The data source is the Approximated API (a trusted third-party service)
- The nonce-based CSP (`script-src 'nonce-...'`) would block injected `<script>` tags unless they carry the nonce
- Event handler attributes (`onclick`, etc.) and `javascript:` URIs would still execute

**Remediation:** Pass the API response through DOMPurify before DOM insertion (the application already imports DOMPurify for `GlobalBroadcast.vue`). Alternatively, migrate to a component-based approach that constructs DOM elements programmatically rather than injecting raw HTML.

---

### L-1: Secure Cookie Flag Conditional on Environment Variable

**Severity:** Low\
**Component:** Session management\
**File:** `lib/onetime/boot.rb:80-85`, `lib/onetime/session.rb`

**Description:** The `secure` cookie flag is set conditionally based on the `SSL` environment variable. If `SSL` is not explicitly set to `true`, session cookies may lack the Secure flag and be transmitted over HTTP.

**Evidence:**
```ruby
SESSION_DEFAULTS = {
  'httponly' => true,
  'same_site' => 'lax',
  # 'secure' is set based on OT.conf.dig('site', 'ssl')
}
```

**Mitigating factors:**
- HttpOnly is always `true` and SameSite is always `Lax`
- The application logs a warning when a secure cookie is dropped over non-SSL
- Most production deployments use TLS termination with the SSL flag set

**Remediation:** Default `secure` to `true` in production configurations. Consider auto-detecting HTTPS from `X-Forwarded-Proto` or `Rack::Request#ssl?` as a fallback.

---

### L-2: Cookie Tossing Protection Disabled by Default

**Severity:** Low\
**Component:** Session management\
**File:** `etc/defaults/config.defaults.yaml`, `lib/onetime/middleware/security.rb`

**Description:** `Rack::Protection::CookieTossing` middleware defaults to `false`. Cookie tossing attacks require control of a sibling subdomain.

**Mitigating factors:** The HMAC verification on session data detects tampering and generates a new session ID, preventing session injection even if a cookie is tossed.

**Remediation:** Consider enabling by default for multi-subdomain deployments.

---

### L-3: Session IDs Logged at Trace Level

**Severity:** Low\
**Component:** Session management / Logging\
**File:** `lib/onetime/session.rb:391-393,534,742-744`

**Description:** Full session IDs are included in structured log entries at trace level. If trace logging is ever enabled in production, session IDs would appear in log files, enabling session hijacking by anyone with log access.

**Mitigating factors:** Trace-level logging should never be enabled in production.

**Remediation:** Truncate or hash session IDs in all log output (e.g., log only first 8 characters). Add a configuration guardrail that prevents trace-level session logging in production.

---

### L-4: Auth State Logged at Trace Level

**Severity:** Low\
**Component:** Session management / Logging\
**File:** `lib/onetime/session.rb:742-755`

**Description:** The "Session saved successfully" trace log entry includes `account_id`, `external_id`, `authenticated_at`, `two_factor_auth_setup`, `awaiting_mfa`, and `session_keys`. This reveals authentication state details.

**Mitigating factors:** Trace-level only; should never appear in production logs.

**Remediation:** Same as L-3 — truncate sensitive fields and guard against trace in production.

---

### L-5: No Dedicated Rate Limiter on Magic Link Requests

**Severity:** Low\
**Component:** Authentication (Rodauth)\
**File:** `rodauth/lib/rodauth/features/email_auth.rb:33`

**Description:** Magic link (email auth) requests rely on Rodauth's built-in `email_auth_skip_resend_email_within` throttle (300 seconds / 5 minutes per account). There is no dedicated IP-based rate limiter equivalent to those on password reset or login.

**Mitigating factors:**
- 5-minute per-account resend throttle limits to ~288 emails/day per account
- If requests route through the login flow, the login rate limiter applies

**Remediation:** Add an IP-based rate limiter to the email-auth request route, consistent with the pattern used for password reset (`ResetRequestRateLimiter`) and account creation (`CreateAccountRateLimiter`).

---

### L-6: Unlock Account Route Reveals Account Existence

**Severity:** Low\
**Component:** Authentication (Rodauth)\
**File:** `rodauth/lib/rodauth/features/lockout.rb:75-96`

**Description:** The unlock account request route returns different responses for existing vs. non-existing accounts. This is a minor enumeration vector but requires the attacker to know or guess that the target account is locked.

**Remediation:** Return identical responses regardless of account existence on the unlock route.

---

### L-7: Deprecated useFormSubmission Composable Lacks Redirect Validation

**Severity:** Low\
**Component:** Frontend (Vue SPA)\
**File:** `src/shared/composables/useFormSubmission.ts:126`

**Description:** The deprecated `useFormSubmission` composable navigates to `options.redirectUrl` without validation. Currently all callers pass hardcoded internal paths, but a future caller could introduce an open redirect.

**Evidence:**
```typescript
if (options.redirectUrl) {
    setTimeout(() => {
        window.location.href = options.redirectUrl!;
    }, options.redirectDelay || 3000);
}
```

**Remediation:** Add `isValidInternalPath()` validation before navigating, matching the pattern used elsewhere in the codebase.

---

### L-8: Dev-Only Dependency Vulnerabilities

**Severity:** Low\
**Component:** Supply chain (npm)\
**Dependencies:** `js-yaml` (GHSA-52cp-r559-cp3m, quadratic DoS), `fast-uri` x2 (GHSA-v2hh-gcrm-f6hx, GHSA-4c8g-83qw-93j6, host confusion)

**Description:** `pnpm audit` reports 3 high and 1 moderate advisory, all in transitive dev dependencies (`@apidevtools/swagger-parser`, `@intlify/eslint-plugin-vue-i18n`). None are production runtime dependencies.

**Remediation:** Update affected dev dependencies when compatible versions are available.

---

## Positive Security Findings

The following security controls were verified as correctly implemented:

### Core Secret Security
- **Atomic one-time reveal** via Redis Lua compare-and-set script prevents double-read race conditions. The Lua script atomically checks the current state against allowed from-states and transitions to the new state in a single Redis call.
- **Secret identifiers** use 256-bit CSPRNG random + 64-bit HMAC-SHA256 tag, base-36 encoded. Verification uses `OpenSSL.secure_compare` (constant-time).
- **Encryption at rest** with AES-256-GCM or XChaCha20-Poly1305, per-field HKDF key derivation (RFC 5869) from a single root SECRET. Per-field keys incorporate field name, record identifier, and class name.
- **ConcealedString wrapper** prevents accidental plaintext leakage through serialization, logging, or debugging. All `to_*` methods return `[CONCEALED]`; `to_json` raises `SerializerError`.

### Session Security
- **256-bit session IDs** via CSPRNG (`SecureRandom`, 64-char hex)
- **Session data encrypted** at rest in Redis: JSON → AES-256-GCM → Base64 → HMAC signed
- **HKDF-derived keys** for session encryption and HMAC (separate key material)
- **Session fixation protection**: tampered sessions generate new IDs and empty data
- **Session destruction on logout**: `session.destroy` deletes from Redis and rotates ID
- **Active sessions tracking** with dual deadlines (24h inactivity, 30-day absolute)
- **Cookie flags**: HttpOnly always true, SameSite Lax, Secure when SSL configured
- **Cookie-only sessions**: `cookie_only: true` prevents URL-param session fixation

### Authentication
- **Argon2id** password hashing with `t_cost=2, m_cost=16 (64 MiB), p_cost=1` — exceeds OWASP minimums
- **TOTP replay protection** via `last_use` column with interval enforcement
- **TOTP secrets HMAC-protected** in database (`otp_keys_use_hmac? true`)
- **WebAuthn challenges** HMAC-signed and timing-safe verified; sign count checked
- **Recovery codes** with 64-bit CSPRNG entropy, base-36 encoded
- **Account ID obfuscation** via format-preserving encryption in token URLs
- **Password reset enumeration-safe** with generic responses regardless of account existence
- **Two-tier rate limiting** on login (5/15min per email+IP), password reset (10/hour per IP), account creation (10/hour per IP) with atomic Lua scripts

### SSO Security
- **Issuer-scoped identities** prevent cross-tenant account takeover (compound key: provider + issuer + uid)
- **PKCE enabled** for OIDC flows
- **SSO connect intent** atomic and time-bounded (5-minute TTL, GETDEL consume-on-read)
- **SsoLinkChallenge** tokens: 256-bit, 5-minute TTL, delete-on-consume
- **SsoLinkVerification** tokens: 256-bit, 15-minute TTL, email-only delivery, password watermark invalidation
- **Phase-3 auto-link** opt-in per-provider with `refuse_issuerless_on_tenant?` blocking GitHub/Google on tenant surfaces

### CSRF & CSP
- **CSRF protection** via `Rack::Protection::AuthenticityToken` with smart bypass for API-key auth, SSO routes, webhooks
- **Strict nonce-based CSP**: `script-src 'nonce-...'` (no `unsafe-inline`, no `unsafe-eval`), `default-src 'none'`, `frame-ancestors 'none'`
- **Single JS bundle** (no code splitting) to simplify nonce management
- **Zod v4 JIT disabled** (`z.config({ jitless: true })`) to prevent CSP violations from `new Function()`

### Frontend Security
- **Single `v-html` usage** properly sanitized through DOMPurify with restrictive config (only `<a>` tags, `https`/`http`/`mailto` schemes, forced `rel="noopener noreferrer"`)
- **No `eval()`, `Function()`, or `document.write`** in application code
- **No `postMessage`** usage (eliminates cross-origin messaging attacks)
- **No credentials in client-side code** (`VITE_` prefix convention enforced)
- **httpOnly session cookies** (no localStorage tokens)
- **Comprehensive redirect validation** with `isValidInternalPath()`, protocol injection checks, and strict Stripe checkout URL allowlist
- **Clickjacking protection** dual-layered: CSP `frame-ancestors 'none'` + `X-Frame-Options`

### Data Safety
- **No `Marshal.load`** on untrusted data (explicit security tests verify this)
- **No `YAML.load`** on untrusted data (only in test files with trusted input)
- **No command injection** vectors in web-facing code
- **JSON.parse** used exclusively for Redis data deserialization
- **Key derivation verifier** at boot time detects wrong SECRET (prevents silent data loss)

### Deployment
- **Non-root container** (uid 1001, `appuser`) in production Docker image
- **Pinned base image** with SHA256 digest
- **No hardcoded secrets** in codebase; all generated by `bin/setup --init`
- **HSTS** enabled via `Rack::Protection::StrictTransport`

---

## Risk Register

| ID | Finding | Severity | Exploitability | Business Impact | Status |
|----|---------|----------|---------------|-----------------|--------|
| M-1 | Login enumeration | Medium | Moderate (rate-limited) | Privacy — reveals registered emails | Open |
| M-2 | Registration enumeration | Medium | Moderate (rate-limited) | Privacy — reveals registered emails | Open |
| M-3 | HTTP security headers as meta tags only | Medium | Low (requires other vuln) | Defense-in-depth gap; referrer leakage risk for secret URLs | Open |
| M-4 | Vendored DNS widget XSS | Medium | Low (requires API compromise) | XSS in admin UI only | Open |
| L-1 | Secure cookie conditional on env var | Low | Low (config-dependent) | Session hijack risk on misconfigured deployments | Open |
| L-2 | Cookie tossing disabled by default | Low | Very Low (requires subdomain control) | Mitigated by HMAC session verification | Open |
| L-3 | Session IDs in trace logs | Low | Very Low (trace must be enabled) | Session hijack if logs compromised | Open |
| L-4 | Auth state in trace logs | Low | Very Low (trace must be enabled) | Information disclosure | Open |
| L-5 | No IP rate limit on magic link requests | Low | Low (per-account throttle exists) | Email flooding limited to 288/day/account | Open |
| L-6 | Unlock route enumeration | Low | Very Low (requires locked account knowledge) | Minor privacy concern | Open |
| L-7 | Deprecated composable missing redirect validation | Low | Very Low (no current callers pass user input) | Latent open redirect | Open |
| L-8 | Dev dependency vulnerabilities | Low | N/A (not in production) | Build-time risk only | Open |

---

## Delta from Prior Audits

All findings from prior audits remain resolved:

- **2026-07-06**: 3 HIGH (CSRF bypass, credential defaults, OmniAuth auto-link), 11 MEDIUM — all fixed
- **2026-07-19**: 0 confirmed vulnerabilities (3 HIGH session findings were false positives)
- **2026-07-30**: 5 findings (session revocation parity, rate limiting gaps, dead code) — all fixed

New areas addressed in this audit not covered previously:
- SSO connect intent security (SsoLinkChallenge, SsoLinkVerification tokens)
- Vendored third-party DNS widget
- Comprehensive frontend redirect validation analysis
- ConcealedString serialization safety
- Zod JIT and CSP interaction
- Account ID obfuscation in auth tokens

---

## Methodology

**Analysis type:** Static analysis and architecture review\
**Tools:** Manual code review, grep-based pattern matching, dependency audit (`pnpm audit`)\
**Approach:** Six parallel analysis tracks covering:
1. Authentication & session management
2. Redis & data layer security
3. API & input validation
4. SPA & frontend security
5. Supply chain & cryptography
6. Business logic & race conditions

Each track independently investigated its domain, with findings cross-referenced and deduplicated. Prior audit reports were reviewed for regression testing.

**Out of scope:** Dynamic testing (no running application), penetration testing, social engineering, physical security.

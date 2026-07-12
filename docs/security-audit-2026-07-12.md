# Security Audit Report: OneTimeSecret

**Date:** 2026-07-12
**Scope:** Full application security analysis across 6 repositories
**Auditor:** Automated security analysis (Claude Code)
**Application Version:** Branch `develop` at HEAD

---

## Executive Summary

OneTimeSecret demonstrates strong security engineering in its core product function (one-time secret reveal). The cryptographic primitives, atomic state management, and session handling are well-designed and correctly implemented. No critical or high-severity vulnerabilities were identified. The findings are primarily in operational hardening (middleware defaults, rate limiting gaps, credential management in deployment configs) rather than fundamental design flaws.

**Finding Distribution:**

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 10 |
| Low | 10 |
| Informational | 5 |

*(Counts reflect the post-audit re-verification below: M-1 and M-10 were downgraded from Medium to the Low–Medium band after checking source directly.)*

---

## Findings

### MEDIUM Severity

#### M-1: Account Lockout Enables Time-Bounded Denial-of-Service

**File:** `apps/web/auth/config/features/lockout.rb:15-16`
**Category:** Authentication / Availability

After 5 failed login attempts (`max_invalid_logins 5`) against any account, Rodauth's `lockout` feature locks that account.

**Correction (post-audit code verification):** An earlier draft of this finding described the lockout as "permanent until admin intervention." That is inaccurate. The repository's own Rodauth reference (`apps/web/auth/docs/rodauth-reference-2.41+.md:281`) documents `account_lockouts_deadline_interval` defaulting to **86400 seconds (1 day)** of auto-unlock, and the `lockout` feature exposes a self-service `unlock_account` email route (same reference, lines 290–300). The lockout is therefore **time-bounded (~24h) and self-recoverable**, not permanent.

**Exploit scenario:** An attacker who knows target email addresses submits 5 wrong passwords per account, locking each victim out for up to ~24 hours (renewable by repeating). This is a harassment / nuisance availability attack against known users, not a permanent account takeover-adjacent lockout. Users can also self-unlock via the email flow if it is exposed in the UI.

**Remediation:** Uncomment line 16 to shorten the auto-unlock window (e.g., to 1 hour) and reduce the harassment window. Note: verify the exact DSL method name against the installed Rodauth version — the standard setter is `account_lockouts_deadline_interval`; confirm `lockout_expiration_default` resolves (it may be a wrapper/alias) before relying on the commented line. Consider pairing with per-IP rate limiting (M-2) so an attacker cannot cheaply lock many accounts from one source.

---

#### M-2: No Per-IP Rate Limiting on Login Endpoints

**File:** `apps/web/auth/config/hooks/login.rb`
**Category:** Authentication / Brute Force

Rate limiting is per-account only (via Rodauth's lockout feature: 5 attempts per account). There is no per-IP rate limiting. An attacker can spray a small number of common passwords against unlimited accounts from a single IP without triggering any blocking mechanism.

**Exploit scenario:** Credential stuffing: try 4 passwords (below lockout threshold) against thousands of accounts. Each account allows 5 attempts, and there is no aggregate IP-level limit.

**Remediation:** Add per-IP rate limiting middleware (e.g., `rack-attack` or a custom Rack middleware) to limit total authentication attempts per source IP regardless of target account.

---

#### M-3: Passphrase Rate Limiting is Per-Secret Only

**File:** `lib/onetime/security/passphrase_rate_limiter.rb`
**Category:** Business Logic / Brute Force

The passphrase rate limiter tracks attempts per secret identifier (`passphrase:attempts:{secret_id}`). An attacker can distribute guesses across different secrets or use multiple IPs against the same secret without hitting a broader rate limit.

**Exploit scenario:** If an attacker knows multiple secret URLs with the same passphrase (e.g., from a predictable pattern), they get 5 attempts per secret. Against a weak passphrase, distributed attempts across secrets could succeed.

**Remediation:** Consider supplementing with per-IP rate limiting on the reveal endpoint, or a global rate limiter that triggers after N total passphrase failures from the same source.

---

#### M-4: Redis/Valkey Runs Without Authentication

**File:** `docker/compose/docker-compose.simple.yml:66-73`, `etc/examples/valkey.conf:7`
**Category:** Deployment / Data Protection

The Valkey container is started without `--requirepass`. While the simple compose binds to localhost only (127.0.0.1:6379), the full compose uses Docker bridge networking where any container on the bridge can connect to Valkey without authentication.

**Exploit scenario:** A compromised container on the Docker network (e.g., via a dependency vulnerability in the Node build stage or RabbitMQ) connects directly to Valkey and reads/modifies all stored data including encrypted secrets, session data, and API tokens.

**Remediation:** Add `--requirepass` to the Valkey command in all compose files and include the password in the `REDIS_URL`/`VALKEY_URL` connection string. Use the `${VAR:?error}` pattern to require it at startup.

---

#### M-5: RabbitMQ Default Credentials

**File:** `docker/compose/docker-compose.full.yml:149-150`
**Category:** Deployment / Credential Management

`RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-guest}` and `RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:-guest}`. If operators do not override these environment variables, the default weak credentials are used.

**Exploit scenario:** Attacker with network access to the Docker bridge (see M-4) connects to RabbitMQ management or AMQP port with `guest:guest`. This allows queue manipulation, message inspection, and potentially message injection into job processing queues.

**Remediation:** Require `RABBITMQ_USER` and `RABBITMQ_PASS` with `${RABBITMQ_USER:?RABBITMQ_USER must be set}` guard syntax, matching the pattern already used for `SECRET`.

---

#### M-6: Clickjacking Protection Disabled by Default

**File:** `etc/defaults/config.defaults.yaml:338`
**Category:** Frontend / Clickjacking

`MIDDLEWARE_FRAME_OPTIONS` defaults to `false`. The application does not set `X-Frame-Options` or `frame-ancestors` CSP directive by default, allowing embedding in attacker-controlled iframes.

**Exploit scenario:** An attacker embeds the authenticated application in an invisible iframe on a malicious page. A victim who is logged in could be tricked into clicking UI elements (e.g., "Burn Secret", "Reveal Secret", or account actions) through carefully positioned overlays.

**Remediation:** Set `MIDDLEWARE_FRAME_OPTIONS` to `true` by default, or ensure the CSP includes `frame-ancestors 'self'`.

---

#### M-7: HSTS (Strict-Transport-Security) Disabled by Default

**File:** `etc/defaults/config.defaults.yaml:354`
**Category:** Transport Security

`MIDDLEWARE_STRICT_TRANSPORT` defaults to `false`. Even when SSL is enabled, the application does not advertise HSTS, leaving users vulnerable to SSL-stripping attacks on first visit.

**Exploit scenario:** A user accesses the application over an insecure network. An active MITM attacker downgrades the initial HTTP request before the redirect to HTTPS, intercepting credentials or session cookies.

**Remediation:** Enable HSTS by default when `SSL=true`. Set `max-age` to at least 31536000 (1 year) and include `includeSubDomains`.

---

#### M-8: Secret Verifier Defaults to 'warn' Mode

**File:** `lib/onetime/secret_verifier.rb:59`
**Category:** Operational Security / Key Management

When `site.secret_verifier_mode` is unset or unrecognized, it defaults to `'warn'`. A wrong SECRET (key rotation mistake, wrong Redis instance) allows the app to boot normally. New secrets work fine, but all historical secrets silently fail to decrypt only when recipients try to reveal them.

**Exploit scenario:** An operator accidentally regenerates the SECRET or deploys against the wrong Redis instance. The application appears healthy. Failure is only observed days later when recipients report undecryptable secrets, by which time the original data may be irrecoverable.

**Remediation:** Consider changing the default to `'enforce'` for new installations, or at minimum log a prominent startup warning. Document this prominently in deployment guides.

---

#### M-9: API Tokens Stored as Plaintext in Redis

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:67`
**Category:** Data Protection / Credentials

API tokens (used for HTTP Basic Auth) are stored as plaintext string fields in Redis, unlike secret content and session data which are encrypted at rest. If Redis is compromised (see M-4), all API tokens are immediately usable.

**Exploit scenario:** Attacker gains read access to Redis (via M-4 or a Redis vulnerability). They extract all API tokens in plaintext and use them for authenticated API access to any account.

**Remediation:** Either hash API tokens (store only the hash, compare hashes on auth) or use `encrypted_field` for the `apitoken` field. Hashing is preferred since it eliminates the ability to display the token after creation.

---

#### M-10: SVG Upload Accepts Arbitrary Content Without Sanitization

**File:** `apps/api/domains/logic/domains/update_domain_image.rb:14-18`
**Category:** Input Validation / Stored XSS

The `IMAGE_MIME_TYPES` allowlist includes `image/svg+xml`. SVG files can contain embedded JavaScript (`<script>` tags, event handlers like `onload`). The uploaded file content is stored as Base64 without SVG-specific sanitization. The MIME type is client-asserted, not verified by magic bytes.

**Exploit scenario:** An organization admin uploads a malicious SVG logo containing JavaScript. When rendered in other users' browsers via the branded share page (depending on rendering method: `<img>` is safe, `<object>` or inline SVG is not), the embedded script executes in the application's origin.

**Mitigations in place (post-audit verification — these substantially lower real-world severity):**
- **Storage is confirmed unsanitized:** `image/svg+xml` is in the allowlist (`update_domain_image.rb:16`), the content type is client-asserted (`@content_type = @image['type']`, line 74), `FastImage` is used only for dimensions, and the raw bytes are stored Base64 with no SVG sanitization or magic-byte check. This part of the finding holds.
- **The audience is not the general public via this path.** The read endpoint `GetDomainImage` (`get_domain_image.rb:43-61`) is gated behind the `custom_branding` entitlement **and** org-membership/domain-scope checks, and returns the image as a JSON `record` (base64 `encoded` + `content_type`), not as a directly-served document. Both uploader and viewer through this path are members of the same organization.
- **Script execution is not established.** Whether the payload runs depends entirely on how the SPA renders the returned data. If it builds a `data:image/svg+xml;base64,…` URI and assigns it to an `<img>` `src` (the typical pattern), embedded scripts do **not** execute. Inline-`<svg>` injection or `<object>`/`<iframe>` rendering would execute. This was not verified and requires tracing the Vue brand-page components. There may also be a separate public serving path for the branded homepage logo; if one exists and renders SVG as a document, severity rises to genuine public stored-XSS.

**Revised assessment:** Confirmed input-validation gap (unsanitized SVG accepted and stored). Exploitability as XSS is **unconfirmed and likely low** given the entitlement-gated same-org audience and `<img>`-style rendering assumption. Treat as Low–Medium pending dynamic verification of the SPA render path and any public logo endpoint.

**Remediation:** Still worth fixing defensively — remove `image/svg+xml` from the allowlist, or sanitize server-side (strip `<script>`, event handlers, `<foreignObject>`) before storage, and add magic-byte validation so the stored `content_type` cannot be spoofed. Ensure the SPA renders logos via `<img>`/CSS `background-image`, never inline SVG.

---

#### M-11: CSRF Token Not Validated for Session-Authenticated API Requests

**File:** `lib/onetime/middleware/security.rb:142`
**Category:** CSRF / API Security

The CSRF `except` lambda returns `true` for ALL paths starting with `/api/`, completely bypassing CSRF validation. V2/V3 APIs support session-based authentication (the SPA uses it). While the frontend voluntarily sends `X-CSRF-Token`, the server does not validate it for `/api/*` paths.

**Exploit scenario:** A user authenticated via session cookie visits a malicious page. That page makes cross-origin POST requests to `/api/v2/secrets` (creating secrets on behalf of the victim). The `SameSite=lax` cookie mitigates most cross-site POST attacks but does not protect against same-site subdomain attacks.

**Code contradicts its own documented intent (post-audit verification):** The comment block above the lambda (`security.rb:115-117`) states that API v2/v3 session requests "require CSRF tokens unless Basic Auth credentials are provided (the allow_if lambda checks for this)." The actual lambda (line 142) does **not** check for Basic Auth — it returns `true` for every path under `/api/`, unconditionally, regardless of authentication method. So a session-cookie-authenticated state-changing request to `/api/v2/*` is never CSRF-validated. The implementation is weaker than the code comment claims, which is itself evidence the current behavior is unintended.

**Mitigations in place:** `SameSite=lax` cookies block cross-site POST requests from third-party origins, which covers the classic CSRF vector. Residual exposure is same-site (sibling subdomain / custom-domain) requests and any future relaxation of the cookie's SameSite attribute.

**Remediation:** Make the lambda match its documentation: only bypass when an `HTTP_AUTHORIZATION` (Basic Auth) header is present; otherwise fall through to token validation for session-authenticated `/api/` requests.

---

#### M-12: Cookie `secure` Flag Depends on ENV Variable Without Production Default

**File:** `etc/defaults/config.defaults.yaml:306`
**Category:** Transport Security

The session cookie's `secure` flag is set to `ENV['SSL'] == 'true' || false`. If a deployment uses TLS termination at a reverse proxy but forgets to set `SSL=true`, session cookies are sent over plain HTTP.

**Exploit scenario:** A production deployment with TLS at the load balancer but without `SSL=true` set will issue non-secure cookies. On any HTTP fallback path, cookies are exposed to network interception.

**Remediation:** Default `secure` to `true` when `RACK_ENV == 'production'`. Only disable explicitly for development.

---

### LOW Severity

#### L-1: httponly Config Not Forwarded to Session Middleware

**File:** `lib/onetime/application/middleware_stack.rb:332-339`
**Category:** Defense-in-Depth

The `httponly` configuration value from `session_config` is not included in the options hash passed to the session middleware. Rack 3.x defaults `httponly` to `true`, so this is not currently exploitable, but an operator who explicitly sets `httponly: false` in config would be silently ignored.

**Remediation:** Add `httponly: session_config['httponly']` to the session middleware options hash.

---

#### L-2: Recovery Codes Use 64-bit Entropy

**File:** `apps/web/auth/config/features/mfa.rb:66-76`
**Category:** Authentication / MFA

Recovery codes are generated with `Familia.generate_trace_id` producing 64-bit random values. While protected by rate limiting (7 OTP auth failures max), 64-bit codes are below the industry standard of 128-bit for security tokens.

**Remediation:** Consider upgrading to `Familia.generate_lite_id` (128-bit) for additional margin against future attack improvements.

---

#### L-3: Dead Deprecated apitoken? Method Uses Non-Constant-Time Comparison

**File:** `lib/onetime/models/customer/features/deprecated_fields.rb:63-65`
**Category:** Cryptography / Timing

A deprecated `apitoken?` method uses `==` (non-constant-time). The main `Customer` class overrides it with `Rack::Utils.secure_compare` at line 268-272, so this code is unreachable via normal MRO. However, its presence risks accidental use if the override is removed.

**Remediation:** Delete the deprecated method entirely.

---

#### L-4: Non-Constant-Time Hash Comparison in Recipient Lookup

**File:** `lib/onetime/models/custom_domain/incoming_config.rb:162-168`
**Category:** Cryptography / Timing

Uses `==` for hash comparison in `lookup_recipient_email`. Since this iterates over a small list (max 20) and the hash requires knowledge of the site secret, the practical impact is minimal.

**Remediation:** Use `Rack::Utils.secure_compare` in the equality check.

---

#### L-5: Unpinned Production Gem Versions

**File:** `Gemfile:52-66`
**Category:** Supply Chain

Several production gems have no version constraints (httparty, mail, mustache, public_suffix, sanitize, tilt, sendgrid-ruby, sentry-ruby, stripe). The lockfile mitigates immediate risk, but missing constraints allow silent major version drift on routine `bundle update`.

**Remediation:** Pin at least major.minor versions for all production gems (e.g., `gem 'httparty', '~> 0.24'`).

---

#### L-6: File Upload MIME Type Not Server-Side Validated

**File:** `apps/api/domains/logic/domains/update_domain_image.rb`
**Category:** Input Validation

The domain image upload endpoint accepts the client-provided MIME type without server-side magic-byte verification. Images are stored as Base64 and served with the stored content_type, not executed server-side, which limits the impact.

**Remediation:** Add server-side magic-byte validation (e.g., using the `marcel` gem or checking the first few bytes) to confirm the uploaded content matches the declared MIME type.

---

#### L-7: Argon2 Memory Cost Below Current OWASP Recommendation

**File:** `lib/onetime/models/features/passphrase_hashing.rb:68-74`
**Category:** Cryptography / Password Hashing

Production Argon2id parameters are `t_cost: 2, m_cost: 16 (64KB), p_cost: 1`. The memory cost of 64KB is below the OWASP 2024 recommendation of 47MB (m_cost: 19). For secret passphrases which users choose and may be weak, higher parameters would provide better resistance against GPU-accelerated offline attacks.

**Remediation:** Consider increasing to `t_cost: 3, m_cost: 19, p_cost: 1` if server resources allow. Existing hashes remain verifiable; new hashes would use stronger parameters.

---

#### L-8: Redis TLS Not Documented or Surfaced in Defaults

**File:** `etc/defaults/config.defaults.yaml:612-619`
**Category:** Transport Security / Documentation

The default Redis URI uses `redis://` (unencrypted). While the code supports `rediss://` for TLS, this is not documented in the configuration reference or surfaced as an option in the default config.

**Remediation:** Document `rediss://` URI usage and TLS configuration in the deployment/operations guide. Consider adding explicit `ssl_params` configuration options.

---

### INFORMATIONAL

#### I-1: Only 4 Recovery Codes Generated

**File:** `apps/web/auth/config/features/mfa.rb:14`

`RECOVERY_CODES_LIMIT = 4` is lower than the industry standard of 8-10. Users may exhaust their codes quickly.

---

#### I-2: Staging Environment Headers in Production Config

**File:** `fly.toml:47-48`

Custom headers `Onetime-Env = 'staging'` and `Onetime-Region = 'ams'` leak deployment topology information.

---

#### I-3: Development Auth Strategies Have Multiple Guards

**Files:** `lib/onetime/application/auth_strategies/dev_basic_auth_strategy.rb`, `dev_session_auth_strategy.rb`

Both strategies raise `SecurityError` if registration is attempted in production mode. They require both `DEV_BASIC_AUTH=true` env var AND `RACK_ENV=development`. Defense-in-depth is properly implemented.

---

#### I-4: YAML.load in Test Files

Multiple test files under `try/` and `spec/` use `YAML.load` instead of `YAML.safe_load`. These are non-production code paths. Modern Ruby (Psych 4+) defaults to safe mode.

---

#### I-5: Secret Status Endpoint Reveals Metadata Without Authentication

**File:** `apps/api/v2/logic/secrets/show_secret_status.rb:28-30`

The `/secret/:identifier/status` endpoint (noauth) returns state, lifespan, has_passphrase flag, and timestamps given a secret identifier. Since identifiers are 256-bit HMAC-signed values (unguessable), this is a design choice rather than a vulnerability. The identifier itself is the capability token.

---

## Security Strengths

The following areas demonstrate excellent security engineering:

1. **Atomic one-time reveal:** Redis Lua CAS script ensures exactly-one-reveal with no race conditions. The `win_reveal_claim!` pattern is correct and well-documented.

2. **Cryptographic design:** HKDF (RFC 5869) with purpose-separated `info` strings, AES-256-GCM authenticated encryption, per-field key derivation binding ciphertext to its record/field. Key rotation supported with version-tagged envelopes.

3. **Session security:** 256-bit session IDs, AES-256-GCM encrypted session data at rest, HMAC-SHA256 envelope verification with constant-time comparison, HKDF-derived subkeys.

4. **CSRF protection:** Masked tokens (XOR one-time pad) mitigate BREACH attacks. Proper bypass logic for SSO (OAuth state), API (Basic Auth), and webhook (signature verification) routes.

5. **Input sanitization:** Centralized `InputSanitizers` module with strict allowlists. Iterative decode-then-strip for multiply-encoded payloads. No mass-assignment patterns.

6. **No unsafe deserialization:** `Marshal.load` explicitly excluded with regression tests. All production code uses `JSON.parse` and `YAML.safe_load`.

7. **Verifiable identifiers:** HMAC-signed random IDs (256-bit random + 64-bit HMAC tag) with constant-time verification prevent forgery and enumeration.

8. **Docker security:** Multi-stage builds, non-root user (UID 1001), SHA256-pinned base images, no secrets in image layers, `.dockerignore` excludes `.env*`.

9. **CSP implementation:** Nonce-based Content Security Policy generated per-request. No `unsafe-inline` or `unsafe-eval` directives. All assets bundled and self-hosted.

10. **Admin interface protection:** Multi-layer (role-based auth + optional CIDR allowlist + returns 404 not 403 to hide existence).

---

## Risk Register

| ID | Finding | Likelihood | Impact | Risk | CVSS Est. |
|----|---------|-----------|--------|------|-----------|
| M-1 | Time-bounded (~24h) account lockout DoS | High | Low | Low–Med | 4.3 |
| M-2 | No per-IP login rate limiting | High | Medium | Medium | 5.3 |
| M-3 | Per-secret-only passphrase rate limit | Medium | Medium | Medium | 4.8 |
| M-4 | Redis without authentication | Medium | High | Medium | 6.5 |
| M-5 | RabbitMQ default credentials | Medium | Medium | Medium | 5.0 |
| M-6 | Clickjacking (no frame protection) | Medium | Medium | Medium | 4.7 |
| M-7 | No HSTS header | Medium | Medium | Medium | 4.7 |
| M-8 | Secret verifier warn-only mode | Low | High | Medium | 4.2 |
| M-9 | Plaintext API tokens in Redis | Low | High | Medium | 5.5 |
| M-10 | Unsanitized SVG upload (XSS unconfirmed) | Low | Med* | Low–Med | 4.0 |
| M-11 | CSRF bypass for session-auth API | Low | Medium | Medium | 4.3 |
| M-12 | Cookie secure flag not default in prod | Medium | Medium | Medium | 4.7 |
| L-1 | httponly not forwarded | Low | Low | Low | 2.0 |
| L-2 | 64-bit recovery codes | Low | Low | Low | 2.5 |
| L-3 | Dead non-constant-time method | Very Low | Medium | Low | 1.5 |
| L-4 | Recipient lookup timing | Very Low | Low | Low | 1.5 |
| L-5 | Unpinned gem versions | Low | Medium | Low | 3.0 |
| L-6 | Upload MIME not validated | Low | Low | Low | 2.5 |
| L-7 | Argon2 memory cost below OWASP 2024 | Low | Medium | Low | 3.0 |
| L-8 | Redis TLS undocumented | Low | Medium | Low | 3.0 |

---

## Recommended Prioritization

### Immediate (next deploy cycle)

1. **M-1:** Set `lockout_expiration_default` to 1800-3600 seconds
2. **M-6:** Enable `MIDDLEWARE_FRAME_OPTIONS=true` by default
3. **M-7:** Enable `MIDDLEWARE_STRICT_TRANSPORT=true` when SSL=true
4. **M-12:** Default cookie `secure` to `true` when `RACK_ENV == 'production'`

### Short-term (next sprint)

5. **M-2:** Add per-IP rate limiting middleware for auth endpoints
6. **M-4:** Add `--requirepass` to Valkey in all compose files
7. **M-5:** Require RabbitMQ credentials with fail-fast guard
8. **M-9:** Hash API tokens instead of storing plaintext
9. **M-10:** Remove `image/svg+xml` from upload allowlist or add SVG sanitization
10. **M-11:** Enforce CSRF for session-auth API calls (bypass only with Basic Auth header)

### Medium-term (next quarter)

11. **M-3:** Add per-IP dimension to passphrase rate limiting
12. **M-8:** Document and consider changing verifier default to 'enforce'
13. **L-8:** Document Redis TLS configuration for production
14. **L-7:** Consider increasing Argon2 memory cost to OWASP 2024 levels

---

## Methodology

- Static analysis of source code across 6 repositories (onetimesecret, rhales, otto, familia, rodauth, rodauth-omniauth)
- Configuration review of all deployment manifests (Docker, Fly.io, compose)
- Dependency analysis (Gemfile.lock, pnpm-lock.yaml)
- Architecture review of auth flows, session management, and secret lifecycle
- Cryptographic design review (key derivation, encryption modes, random generation)
- Input validation and sanitization path tracing
- Race condition analysis of concurrent reveal scenarios

## Post-Audit Verification Status

A second pass re-checked the load-bearing findings directly against source (rather than relying on the initial parallel-agent summaries). Results:

| Finding | Status | Note |
|---------|--------|------|
| M-1 lockout | **Corrected** | Not "permanent" — Rodauth default is ~24h auto-unlock + self-service email unlock. Impact downgraded. |
| M-4 Redis no-auth | Confirmed | Compose files start Valkey without `--requirepass`. |
| M-6 frame_options / M-7 HSTS / M-12 cookie secure | Confirmed | `config.defaults.yaml` defaults all three off/insecure absent explicit env vars. Note: the reference reverse-proxy (Caddy) deployment sets some edge headers, so residual risk is highest for operators who deploy without that edge hardening — these are "insecure-by-default, hardened-if-you-follow-the-deploy-guide" issues. |
| M-9 plaintext API tokens | Confirmed | `base.field :apitoken` (deprecated_fields.rb:19) is a plain field, not `encrypted_field`. Comparison itself is constant-time. |
| M-10 SVG upload | **Corrected** | Storage gap confirmed; XSS exploitability unconfirmed and likely low (entitlement-gated same-org audience, `<img>`-render assumption). Needs dynamic verification. |
| M-11 CSRF /api bypass | **Strengthened** | Confirmed the lambda bypasses all `/api/` unconditionally, contradicting its own code comment which claims a Basic-Auth check exists. |
| L-3 dead apitoken? | Confirmed | Non-constant-time method in `deprecated_fields.rb:63` is overridden by the secure one in `customer.rb:268` via MRO; unreachable but should be deleted. |

**Items still requiring dynamic (running-instance) verification:** M-10 SPA render path and any public logo endpoint; M-11 same-site subdomain reachability under the production cookie/domain layout; whether the `unlock_account` route (M-1) is actually surfaced in the UI.

## Scope Limitations

- No dynamic testing (DAST) was performed against a running instance
- No penetration testing of the production environment
- Third-party library internals (Rodauth, Familia, Otto) reviewed at integration points only
- No review of infrastructure beyond what is defined in repository configuration files

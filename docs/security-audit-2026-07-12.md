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
| Medium | 9 |
| Low | 7 |
| Informational | 4 |

---

## Findings

### MEDIUM Severity

#### M-1: Permanent Account Lockout Enables Denial-of-Service

**File:** `apps/web/auth/config/features/lockout.rb:16`
**Category:** Authentication / Availability

The `lockout_expiration_default` is commented out. Rodauth's default behavior is permanent lockout until admin intervention. After 5 failed login attempts against any account, that account is locked indefinitely.

**Exploit scenario:** An attacker who knows a target's email address submits 5 incorrect passwords, permanently locking the victim out until an administrator manually intervenes.

**Remediation:** Uncomment and set `auth.lockout_expiration_default 3600` (or a suitable value) to enable time-based auto-unlock.

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

#### L-7: Redis TLS Not Documented or Surfaced in Defaults

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
| M-1 | Permanent account lockout DoS | High | Medium | Medium | 5.3 |
| M-2 | No per-IP login rate limiting | High | Medium | Medium | 5.3 |
| M-3 | Per-secret-only passphrase rate limit | Medium | Medium | Medium | 4.8 |
| M-4 | Redis without authentication | Medium | High | Medium | 6.5 |
| M-5 | RabbitMQ default credentials | Medium | Medium | Medium | 5.0 |
| M-6 | Clickjacking (no frame protection) | Medium | Medium | Medium | 4.7 |
| M-7 | No HSTS header | Medium | Medium | Medium | 4.7 |
| M-8 | Secret verifier warn-only mode | Low | High | Medium | 4.2 |
| M-9 | Plaintext API tokens in Redis | Low | High | Medium | 5.5 |
| L-1 | httponly not forwarded | Low | Low | Low | 2.0 |
| L-2 | 64-bit recovery codes | Low | Low | Low | 2.5 |
| L-3 | Dead non-constant-time method | Very Low | Medium | Low | 1.5 |
| L-4 | Recipient lookup timing | Very Low | Low | Low | 1.5 |
| L-5 | Unpinned gem versions | Low | Medium | Low | 3.0 |
| L-6 | Upload MIME not validated | Low | Low | Low | 2.5 |
| L-7 | Redis TLS undocumented | Low | Medium | Low | 3.0 |

---

## Recommended Prioritization

### Immediate (next deploy cycle)

1. **M-1:** Set `lockout_expiration_default` to 1800-3600 seconds
2. **M-6:** Enable `MIDDLEWARE_FRAME_OPTIONS=true` by default
3. **M-7:** Enable `MIDDLEWARE_STRICT_TRANSPORT=true` when SSL=true

### Short-term (next sprint)

4. **M-2:** Add per-IP rate limiting middleware for auth endpoints
5. **M-4:** Add `--requirepass` to Valkey in all compose files
6. **M-5:** Require RabbitMQ credentials with fail-fast guard
7. **M-9:** Hash API tokens instead of storing plaintext

### Medium-term (next quarter)

8. **M-3:** Add per-IP dimension to passphrase rate limiting
9. **M-8:** Document and consider changing verifier default to 'enforce'
10. **L-7:** Document Redis TLS configuration for production

---

## Methodology

- Static analysis of source code across 6 repositories (onetimesecret, rhales, otto, familia, rodauth, rodauth-omniauth)
- Configuration review of all deployment manifests (Docker, Fly.io, compose)
- Dependency analysis (Gemfile.lock, pnpm-lock.yaml)
- Architecture review of auth flows, session management, and secret lifecycle
- Cryptographic design review (key derivation, encryption modes, random generation)
- Input validation and sanitization path tracing
- Race condition analysis of concurrent reveal scenarios

## Scope Limitations

- No dynamic testing (DAST) was performed against a running instance
- No penetration testing of the production environment
- Third-party library internals (Rodauth, Familia, Otto) reviewed at integration points only
- No review of infrastructure beyond what is defined in repository configuration files

# Security Audit Tooling Notes — 2026-08-02

## Environment

- **Ruby:** 3.4.10
- **Node.js:** 22.x (pnpm 10.x)
- **Vue.js:** 3.5.34 (Vite 8.0.6)
- **Redis/Valkey:** Used as primary data store and session backend
- **SQLite3** (dev) / **PostgreSQL** (prod) for auth data (Rodauth)
- **OS:** Linux (container-based)

## Repositories Analyzed

| Repository | Branch | Purpose |
|-----------|--------|---------|
| onetimesecret/onetimesecret | develop | Main application |
| onetimesecret/rhales | HEAD | Frontend build tooling |
| delano/otto | HEAD | Web framework (routing, middleware, CSP) |
| delano/familia | HEAD | Redis ORM with encryption support |
| onetimesecret/rodauth | HEAD | Authentication framework (fork) |
| onetimesecret/rodauth-omniauth | HEAD | SSO integration (fork) |

## Analysis Methods

### Static Analysis
- Manual code review of security-critical paths
- Pattern-based search (grep/ripgrep) for:
  - Unsafe deserialization: `Marshal.load`, `YAML.load`, `eval`, `send`
  - Command injection: `system(`, `exec(`, `IO.popen`, `Open3`
  - XSS sinks: `v-html`, `innerHTML`, `insertAdjacentHTML`, `document.write`
  - Open redirects: `redirect`, `location.href`, `validate_url`
  - Hardcoded secrets: `password=`, `secret=`, `api_key=`, `token=`
  - Weak randomness: `rand(`, `Math.random`, `srand`

### Dependency Audit
- `pnpm audit` for npm package vulnerabilities
- Manual Gemfile.lock review for Ruby gem versions

### Architecture Review
- Middleware stack ordering and configuration
- Session lifecycle (creation, storage, rotation, destruction)
- Encryption key derivation chain (HKDF from root SECRET)
- CSRF protection bypass conditions
- CSP policy construction and nonce management
- Rate limiter implementation (Lua scripts for atomicity)
- SSO identity resolution and cross-tenant isolation

## Key Files Reviewed

### Core Security
- `lib/onetime/models/features/state_cas.rb` — Atomic CAS via Lua script
- `lib/onetime/models/secret/features/secret_state_management.rb` — Reveal lifecycle
- `lib/onetime/key_derivation.rb` — HKDF key derivation
- `lib/onetime/secret_verifier.rb` — Boot-time SECRET validation
- `lib/onetime/session.rb` — Session encryption, HMAC, lifecycle
- `lib/onetime/middleware/security.rb` — Security middleware configuration

### Authentication
- `apps/web/auth/config/base.rb` — Rodauth base configuration
- `apps/web/auth/config/features/argon2.rb` — Password hashing
- `apps/web/auth/config/features/mfa.rb` — TOTP/WebAuthn/recovery
- `apps/web/auth/config/features/omniauth.rb` — SSO configuration
- `apps/web/auth/config/hooks/omniauth.rb` — SSO connect flow
- `apps/web/auth/config/overrides/reset_password_enumeration.rb` — Anti-enumeration

### Encryption (Familia)
- `familia/lib/familia/encryption.rb` — Provider registry
- `familia/lib/familia/features/encrypted_fields.rb` — Per-field encryption
- `familia/lib/familia/features/encrypted_fields/concealed_string.rb` — Leak prevention
- `familia/lib/familia/verifiable_identifier.rb` — Secret URL token generation

### Frontend
- `src/shared/components/ui/GlobalBroadcast.vue` — DOMPurify usage
- `src/utils/redirect.ts` — Redirect validation
- `src/plugins/core/configureZod.ts` — Zod JIT disable
- `src/assets/approximated/dnswidget.v1.js` — Vendored DNS widget
- `vite.config.ts` — Build configuration, env var exposure

### Middleware & CSP
- `lib/onetime/application/middleware_stack.rb` — Universal middleware ordering
- `apps/web/core/middleware/request_setup.rb` — CSP nonce generation
- `otto/lib/otto/security/csp/policy.rb` — CSP policy construction

## Observations

### What's Working Well
1. The atomic CAS pattern for secret reveal is a textbook-correct implementation
2. HKDF key derivation from a single root secret is clean and auditable
3. The ConcealedString wrapper is an effective defense against accidental plaintext leakage
4. Rate limiters use atomic Lua scripts, preventing race conditions in the limiters themselves
5. SSO issuer-scoped identities with multi-phase linking is thorough
6. The single `v-html` usage with DOMPurify is properly implemented
7. CSP is strict nonce-based with no `unsafe-eval` or script `unsafe-inline`

### Areas for Future Audits
1. Dynamic testing of the rate limiters under concurrent load
2. Penetration testing of SSO flows with various IdP configurations
3. Review of billing/Stripe webhook signature validation
4. Memory analysis of ConcealedString lifecycle in long-running processes
5. Redis ACL configuration review in production deployments

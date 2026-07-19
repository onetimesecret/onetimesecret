# Tooling Notes — Security Audit 2026-07-19

## Audit Environment

- **Platform:** Linux 6.18.5, remote container
- **Access:** Full read access to source repositories, root shell
- **Method:** Static analysis and architecture review (no dynamic testing)
- **Repositories examined:**
  - `onetimesecret/onetimesecret` — Main application
  - `delano/familia` — Redis ORM with encryption
  - `onetimesecret/rodauth` — Authentication plugin
  - `onetimesecret/rodauth-omniauth` — SSO integration
  - `onetimesecret/rhales` — (Frontend tooling)

## Tools Used

### Static Analysis
- Manual code review via file reading and grep
- Pattern matching for security-sensitive constructs:
  - `v-html`, `innerHTML`, `eval`, `Function()` — XSS vectors
  - `localStorage`, `sessionStorage` — client-side storage audit
  - `window.location`, `window.open` — redirect patterns
  - `HSETNX`, `setnx`, `exists?` — atomicity patterns
  - `secure_compare`, `constant_time` — timing safety
  - `sanitize`, `DOMPurify`, `escape` — output encoding

### Architecture Review
- Middleware stack ordering analysis
- Auth strategy registration and enforcement verification
- Redis key pattern analysis for rate limiter isolation
- HKDF derivation path tracing (root SECRET → all derived keys)
- Cookie attribute inheritance verification

### Concurrency Analysis
- Redis transaction patterns (MULTI/EXEC, WATCH, Lua scripts)
- TOCTOU identification in check-then-write sequences
- Atomic state transition verification (CAS patterns)

## Reproduction Environment

No local environment changes were made. All analysis was performed via source code reading. To reproduce findings:

### M-1 (Account Creation Race)
```bash
# Requires two concurrent requests to the same signup endpoint
# with the same email address within the Redis RTT window (~1ms)
ab -n 2 -c 2 -p signup_data.txt -T 'application/x-www-form-urlencoded' \
  http://localhost:3000/api/v2/account
```

### M-2 (V1 Passphrase DoS)
```bash
# Create a passphrase-protected secret, then exhaust global rate limit
SECRET_KEY="<obtained-from-create-response>"
for i in $(seq 1 20); do
  curl -s -X POST "http://localhost:3000/api/v1/secret/$SECRET_KEY" \
    -u "test:apikey" -d "passphrase=wrong_$i"
done
# Legitimate user now gets LimitExceeded for 30 minutes
```

### M-3 (Lockout DoS via Rodauth)
```bash
# 5 bad-password attempts trigger 24h lockout
TARGET_EMAIL="victim@example.com"
for i in $(seq 1 5); do
  curl -s -X POST "http://localhost:3000/auth/login" \
    -d "login=$TARGET_EMAIL&password=wrong_$i"
done
# Account locked for 24 hours (Rodauth default)
```

## Files Examined (Selection)

### Security-Critical Backend
| Path | Purpose |
|------|---------|
| `lib/onetime/session.rb` | Session management, encryption codec |
| `lib/onetime/key_derivation.rb` | HKDF key derivation from root SECRET |
| `lib/onetime/security/passphrase_rate_limiter.rb` | Two-tier passphrase throttle |
| `lib/onetime/security/login_rate_limiter.rb` | Two-tier login throttle |
| `lib/onetime/security/input_sanitizers.rb` | Input validation |
| `lib/onetime/middleware/security.rb` | Rack::Protection stack |
| `lib/onetime/middleware/admin_network_isolation.rb` | CIDR-based admin gate |
| `lib/onetime/middleware/csrf_response_header.rb` | CSRF token emission |
| `lib/onetime/application/authorization_policies.rb` | Role enforcement |
| `lib/onetime/application/auth_strategies/` | All auth strategy implementations |
| `lib/onetime/models/features/state_cas.rb` | Atomic state transitions |
| `lib/onetime/models/features/passphrase_hashing.rb` | Argon2id/BCrypt hashing |

### Authentication (Rodauth Mode)
| Path | Purpose |
|------|---------|
| `apps/web/auth/config/features/lockout.rb` | Brute-force protection |
| `apps/web/auth/config/features/mfa.rb` | MFA configuration |
| `apps/web/auth/config/features/webauthn.rb` | WebAuthn/FIDO2 |
| `apps/web/auth/config/features/remember_me.rb` | Remember-me cookie |
| `apps/web/auth/config/hooks/login.rb` | Login flow hooks |
| `apps/web/auth/config/hooks/omniauth.rb` | SSO integration |
| `apps/web/auth/config/hooks/omniauth_tenant.rb` | Multi-tenant SSO |
| `apps/web/auth/operations/detect_mfa_requirement.rb` | MFA decision logic |

### API Layer
| Path | Purpose |
|------|---------|
| `apps/api/v1/controllers/` | V1 API (capability-based) |
| `apps/api/v2/logic/secrets/` | V2 API secret operations |
| `apps/api/colonel/` | Admin API (all routes) |
| `apps/api/account/logic/account/create_account.rb` | Account creation |

### Familia ORM (Encryption)
| Path | Purpose |
|------|---------|
| `familia/lib/familia/encryption/providers/` | AES-GCM + XChaCha20 |
| `familia/lib/familia/verifiable_identifier.rb` | HMAC-signed IDs |
| `familia/lib/familia/horreum/atomic_write.rb` | Atomic persistence |
| `familia/lib/familia/features/encrypted_fields/` | Field-level encryption |

### Frontend
| Path | Purpose |
|------|---------|
| `src/shared/components/ui/GlobalBroadcast.vue` | Only v-html usage |
| `src/plugins/axios/interceptors.ts` | CSRF token management |
| `src/utils/redirect.ts` | Redirect validation |
| `src/shared/stores/` | Storage patterns |

## Limitations

1. **No dynamic testing** — Findings are based on code paths, not runtime behavior
2. **No dependency CVE scan** — Gem/npm versions reviewed manually; automated scanners (bundler-audit, npm audit) not run
3. **No load/stress testing** — Rate limiter bypass under extreme concurrency not tested
4. **Otto gem not fully audited** — CSP directive details are in the Otto routing framework (external dependency)
5. **Production config not reviewed** — Only defaults and Docker Compose examples examined
6. **No Redis ACL review** — Redis access control configuration not examined (deployment-specific)

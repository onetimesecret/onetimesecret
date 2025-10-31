# OneTimeSecret Authentication System

## Documentation

This directory contains the Rodauth-based authentication system for OneTimeSecret.

### Key Documents

1. **[ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md)** - Start here!
   - Why we chose this architecture
   - How we compare to Auth0, Okta, Cognito
   - Industry patterns we use (idempotency, eventual consistency)
   - Alternative approaches we considered
   - When to evolve the architecture

2. **[IMPLEMENTATION_NOTES.md](./IMPLEMENTATION_NOTES.md)** - Operations guide
   - Redis dependency details
   - Idempotency implementation
   - Session state machine
   - Logging and observability
   - Operational runbooks
   - Troubleshooting scenarios

### Quick Reference

**Authentication Flow**:
```
Login → Rodauth validates (SQL) → DetectMfaRequirement → SyncSession → Customer (Redis)
```

**Key Patterns**:
- **Idempotency**: Prevents duplicate execution on retry (5-minute windows)
- **Fail-Open**: Redis down? Authentication still works
- **Eventual Consistency**: Compensating transactions fix temporary inconsistency
- **Correlation IDs**: Track requests end-to-end

**Testing**:
```bash
# Backend (Tryouts)
FAMILIA_DEBUG=0 bundle exec try --agent try/integration/authentication/

# Frontend (Vitest)
pnpm test src/tests/composables/useMfa.spec.ts
```

**Monitoring**:
- Session sync duration: < 50ms target
- Idempotency bypass rate: < 5%
- MFA setup success: > 95%

### File Structure

```
apps/web/auth/
├── README.md                          # This file
├── ARCHITECTURE_DECISIONS.md          # Why we built it this way
├── IMPLEMENTATION_NOTES.md            # How to operate it
├── config.rb                          # Main Rodauth configuration
├── config/
│   ├── base.rb                        # Database, HMAC, JSON settings
│   ├── email.rb                       # Email delivery
│   ├── features/                      # Feature modules (MFA, passwordless, etc.)
│   └── hooks/                         # Lifecycle hooks (login, account, etc.)
├── operations/                        # Business logic
│   ├── sync_session.rb                # Redis-SQL synchronization
│   └── detect_mfa_requirement.rb      # MFA detection logic
├── lib/
│   └── logging.rb                     # Correlation IDs, metrics
├── routes/                            # HTTP endpoints
│   ├── account.rb                     # Account info, MFA status
│   ├── active_sessions.rb             # Session management
│   └── health.rb                      # Health checks
└── migrations/                        # Database schema
    ├── 001_initial.rb                 # Core Rodauth tables
    └── 002_extras.rb                  # Extended features
```

### Common Tasks

**Check authentication status**:
```bash
curl http://localhost:7143/auth/account
```

**Enable MFA for account**:
```javascript
// Frontend (Vue composable)
const { setupMfa, enableMfa } = useMfa()
const setupData = await setupMfa()  // Get QR code
await enableMfa(otpCode, password)  // Verify and enable
```

**Debug session sync issues**:
```bash
# Check for errors
grep "sync_session_error" production.log

# Check Redis
redis-cli KEYS "sync_session:*"

# Check orphaned customers
SELECT COUNT(*) FROM accounts WHERE external_id IS NULL;
```

### Related Work

- **GitHub Issue**: [#1833 - Stabilize Rodauth Architecture](https://github.com/onetimesecret/onetimesecret/issues/1833)
- **Frontend MFA**: `src/composables/useMfa.ts`
- **Tests**: `try/integration/authentication/` and `src/tests/composables/useMfa.spec.ts`

### Questions?

1. **Why dual datastores?** - See [ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md) "The Core Challenge"
2. **How does idempotency work?** - See [IMPLEMENTATION_NOTES.md](./IMPLEMENTATION_NOTES.md) "Idempotency Implementation"
3. **What happens if Redis fails?** - See [IMPLEMENTATION_NOTES.md](./IMPLEMENTATION_NOTES.md) "Redis Dependency > Failure Modes"
4. **How do we compare to Auth0?** - See [ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md) "Industry Comparison"

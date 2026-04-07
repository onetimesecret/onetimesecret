# OneTimeSecret Authentication System

Rodauth-based authentication system with dual-datastore architecture (PostgreSQL/SQLite + Redis).

## Quick Reference

**Authentication Flow**:
```
Login → Rodauth validates (SQL) → DetectMfaRequirement → SyncSession → Customer (Redis)
```

**Key Patterns**:
- **Idempotency**: 5-minute windows prevent duplicate execution on retry
- **Fail-Open**: Redis down? Authentication still works
- **Eventual Consistency**: Compensating transactions fix temporary inconsistency
- **Correlation IDs**: End-to-end request tracking

## Identity Model

Rodauth manages a single global identity pool — one email = one account. Organization membership is resolved post-authentication in Redis via `OrganizationLoader`. This design allows users to belong to multiple organizations with one login and lets SSO accounts merge correctly with password accounts.

Per-organization credential policies (password rules, lockout thresholds, branded reset emails) are delegated to the IdP for SSO-enabled orgs. Password auth uses platform-wide defaults. If tenant-scoped identities become necessary (same email as independent accounts per org), Rodauth queries would need `tenant_id` filtering — see `config/base.rb`.

**Testing**:
```bash
pnpm run test:tryouts:agent try/integration/authentication/
pnpm test src/tests/composables/useMfa.spec.ts
```

**Monitoring Targets**:
- Session sync: < 50ms
- Idempotency bypass: < 5%
- MFA setup success: > 95%

## Common Tasks

**Check authentication status**:
```bash
curl http://localhost:7143/auth/account
```

**Enable MFA**:
```javascript
const { setupMfa, enableMfa } = useMfa()
const setupData = await setupMfa()
await enableMfa(otpCode, password)
```

**Debug session sync**:
```bash
grep "sync_session_error" production.log
redis-cli KEYS "sync_session:*"
```

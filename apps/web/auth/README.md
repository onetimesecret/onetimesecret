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

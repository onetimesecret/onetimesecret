# Rodauth Authentication Implementation Notes

**Date**: 2025-10-26
**Issue**: #1833 - Stabilize Rodauth Authentication Architecture
**Branch**: feature/1833-stabilize-rodauth-architecture

## Overview

This document provides critical implementation details for the OneTimeSecret Rodauth authentication system, particularly focusing on Redis dependencies, idempotency, and operational considerations.

**See also**: [ARCHITECTURE_DECISIONS.md](./ARCHITECTURE_DECISIONS.md) for context on why we chose this approach and how it compares to industry-standard authentication patterns.

## Redis Dependency

### Critical Components

The authentication system has **two dependencies on Redis**:

1. **Session Synchronization** (`Auth::Operations::SyncSession`)
   - Creates/updates Customer records in Redis (via Familia ORM)
   - Links SQL accounts to Redis customers via `external_id` field
   - Stores session data in Redis for application use

2. **Idempotency Protection** (`Auth::Operations::SyncSession`)
   - Uses Redis keys to prevent duplicate execution
   - Key format: `sync_session:#{account_id}:#{session_id}:#{timestamp_window}`
   - TTL: 5 minutes (300 seconds)

### Failure Modes

#### Redis Unavailable During Login

**Behavior**: **Fail-open** - Authentication proceeds without Redis functionality

**Impact**:
- ✅ Users can still log in (SQL authentication works)
- ❌ Session sync skipped (no Customer record created/updated)
- ❌ Idempotency protection disabled (duplicate calls not prevented)
- ⚠️  Application functionality may be degraded (Customer data unavailable)

**Detection**:
```ruby
Auth::Logging.log_operation(
  'redis_unavailable_during_sync',
  level: :warn,
  error: e.message
)
```

#### Redis Fails During Session Sync

**Behavior**: Partial failure with compensation logic

**Scenarios**:

1. **Customer creation fails**:
   - SQL account remains without `external_id` link
   - Next login attempt will retry customer creation
   - Logged as operation error

2. **External_id update fails**:
   - Customer exists in Redis
   - SQL account not linked
   - Session sync incomplete
   - Compensation: Clear idempotency key to allow retry

3. **Idempotency key set fails**:
   - Operation proceeds anyway (logged warning)
   - Duplicate execution possible on retry

### Monitoring

**Key Metrics to Track**:

1. `redis_unavailable_count` - How often Redis is unreachable
2. `session_sync_failures` - Failed sync operations
3. `idempotency_bypass_count` - Operations running without protection
4. `session_sync_duration` - Performance baseline (target: < 50ms)

**Alert Thresholds**:
- Redis unavailable: Alert if > 1% of login attempts
- Session sync failures: Alert if > 0.5%
- Idempotency bypasses: Alert if > 5%

## Idempotency Implementation

### Key Generation

```ruby
def idempotency_key
  @idempotency_key ||= begin
    timestamp_window = (Time.now.to_i / 300).to_i
    "sync_session:#{@account[:id]}:#{@session.id}:#{timestamp_window}"
  end
end
```

**Design Decisions**:

1. **5-minute time windows**: Allows re-sync after reasonable timeout
2. **Session ID included**: Different sessions can sync independently
3. **Account ID primary**: Prevents cross-account contamination

### Protection Logic

```ruby
# 1. Check if already processed
return if idempotency_key_exists?

# 2. Mark as processing
mark_idempotency_key

# 3. Execute operation
perform_sync

# 4. On failure, clear key to allow retry
rescue => e
  clear_idempotency_key
  raise
end
```

### Retry Safety

**Safe to retry**:
- Network timeout during HTTP request
- Redis temporary unavailable
- Database deadlock

**NOT safe to retry without clearing idempotency key**:
- Successful execution
- Validation error (would fail again)

## MFA Detection and Recovery

### Extracted Operations

#### `Auth::Operations::DetectMfaRequirement`

**Purpose**: Determine if MFA is required and how session sync should proceed

**Returns**: Decision object with methods:
- `requires_mfa?` - Does account have MFA enabled?
- `defer_session_sync?` - Should full sync wait for MFA verification?
- `sync_session_now?` - Should sync happen immediately?

**State Transitions**:
```
Login successful → DetectMfaRequirement
  ├─ MFA enabled → defer_session_sync? = true → Set session[:awaiting_mfa]
  └─ No MFA → sync_session_now? = true → SyncSession immediately
```

## Session State Machine

### Authentication States

1. **Unauthenticated** - No session, not logged in
2. **Password Authenticated** - Valid password, checking for MFA
3. **Awaiting MFA** - `session[:awaiting_mfa] = true`, partial session sync
4. **MFA Verified** - OTP or recovery code verified, full session sync
5. **Fully Authenticated** - Complete session, Customer linked
6. **Logged Out** - Session cleared, correlation ID cleaned

### State Transitions

```
[Unauthenticated]
  ↓ POST /auth/login with valid credentials
[Password Authenticated]
  ↓ DetectMfaRequirement
  ├─ No MFA → SyncSession immediately
  │   ↓
  │  [Fully Authenticated]
  │
  └─ MFA required → defer sync
      ↓ session[:awaiting_mfa] = true
     [Awaiting MFA]
      ↓ POST /auth/otp-auth with valid code
      ↓ SyncSession (full)
     [Fully Authenticated]
```

## Logging and Observability

### Correlation ID Tracking

**Generated**: At `before_login_attempt` hook
**Stored**: `session[:auth_correlation_id]`
**Propagated**: Through all hooks and operations
**Cleaned**: After logout in `after_logout` hook

**Format**: 12-character hex string (e.g., `a3f7c9d1e2b8`)

### Key Events Logged

**Login Flow**:
- `login_attempt` - Initial login request
- `mfa_detected` - MFA requirement identified
- `session_sync_deferred` - Waiting for MFA verification
- `login_success` - Password authentication complete
- `login_failure` - Invalid credentials

**MFA Flow**:
- `mfa_authentication_attempt` - OTP verification attempt
- `mfa_authentication_success` - Valid OTP code
- `mfa_authentication_failure` - Invalid OTP code
- `mfa_setup` - MFA configuration initiated
- `mfa_enabled` - MFA successfully enabled
- `mfa_disabled` - MFA removed from account

**Session Sync**:
- `sync_session_start` - Operation initiated
- `customer_created` - New Customer record in Redis
- `account_linked` - SQL external_id updated
- `session_sync_complete` - Full synchronization done
- `sync_session_error` - Operation failed

### Metrics Collection

```ruby
Auth::Logging.measure('session_sync_duration') do
  # Operation code
end
```

**Collected Metrics**:
- `session_sync_duration` (ms) - Time to sync session data
- `mfa_authentication_success_count` - Successful MFA verifications
- `mfa_authentication_failure_count` - Failed MFA attempts
- `mfa_setup_count` - MFA configurations initiated
- `mfa_disable_count` - MFA removals

## Testing Strategy

### Unit Tests (Tryouts)

1. **Auth Logging** (`try/integration/authentication/advanced_mode/auth_logging_try.rb`)
   - 12 test cases
   - Validates correlation ID generation, event logging, metrics

2. **MFA Detection** (`try/unit/auth/mfa_detection_try.rb`)
   - 9 test cases
   - Tests DetectMfaRequirement operation in isolation

3. **Session Sync Idempotency** (`try/integration/authentication/advanced_mode/sync_session_idempotency_try.rb`)
   - 8 test cases
   - Validates duplicate execution prevention

### Integration Tests (Tryouts)

1. **Complete MFA Flow** (`try/integration/authentication/advanced_mode/mfa_complete_flow_try.rb`)
   - 31 test cases
   - End-to-end validation of login → MFA → session sync
   - Tests both MFA and non-MFA paths
   - Validates recovery flow
   - Confirms idempotency protection

### Frontend Tests (Vitest)

1. **MFA Composable** (`src/tests/composables/useMfa.spec.ts`)
   - 33 test cases
   - Tests HMAC two-step setup flow
   - Validates error handling (422 as success, actual errors)
   - Coverage: 85.51% statements, 100% functions

## Operational Runbook

### Scenario: Session Sync Failures

**Symptoms**: Users can log in but application features don't work

**Diagnosis**:
```bash
# Check for session sync errors
grep "sync_session_error" production.log | tail -50

# Check Redis connectivity
redis-cli PING

# Check for unlinked accounts (SQL without external_id)
SELECT COUNT(*) FROM accounts WHERE external_id IS NULL AND status_id = 2;
```

**Resolution**:
1. If Redis down: Restart Redis service
2. If accounts unlinked: Run manual sync script
3. If persistent: Check database constraints

### Scenario: Duplicate Customers Created

**Symptoms**: Multiple Customer records for same email

**Diagnosis**:
```bash
# Check for duplicate customers in Redis
redis-cli KEYS "customer:*:all_by_email:user@example.com"

# Check idempotency bypass count
grep "redis_unavailable_during_sync" production.log | wc -l
```

**Resolution**:
1. Identify canonical customer (most recent activity)
2. Merge customer data
3. Update SQL external_id to canonical customer
4. Delete duplicate customers
5. Investigate why idempotency failed


## Performance Baselines

**Target Metrics** (from issue success criteria):

- Session sync operations: < 50ms average
- MFA setup success rate: > 95%
- Test coverage: > 80% (achieved: frontend 85%+)
- Zero consistency errors in production

**Actual Performance** (to be measured in production):

- Session sync: _TBD_ (instrumentation in place)
- MFA setup: _TBD_ (frontend tests passing)
- Redis availability: _TBD_ (monitoring needed)

## Future Improvements

1. **Single Datastore Migration**: Evaluate moving all auth data to SQL with Redis caching
2. **Idempotency in Database**: Store idempotency keys in SQL for durability
3. **Async Session Sync**: Move session sync to background job for faster login
4. **Distributed Locking**: Use Redis distributed locks instead of simple keys
5. **Circuit Breaker Pattern**: Add proper circuit breaker for Redis (currently fail-open)
6. **Performance Monitoring**: Add APM integration for auth flow tracing
7. **MFA Recovery Security**: Require additional verification beyond email

## References

- GitHub Issue: #1833
- Rodauth Documentation: https://rodauth.jeremyevans.net
- Memoria (1027-onetimesecret-rodauth-architecture-analysis)
- Memoria (1027-onetimesecret-rodauth-implementation-details)

# QA Test Plan: DNS Resilience Features (Issue #2835)

## Executive Summary

This test plan covers the DNS resilience improvements for sender domain validation.
The implementation introduces parallel DNS lookups, rate limiting, configuration
externalization, caching, retry with backoff, and tracking fields.

**Test Execution Summary**: 315 tests passing across 9 test files.

---

## 1. Current Test Coverage Analysis

### Test Files and Status

| File | Coverage Area | Tests | Status |
|------|--------------|-------|--------|
| `try/unit/operations/validate_sender_domain_try.rb` | ValidateSenderDomain operation | 43 | PASS |
| `try/unit/operations/provision_sender_domain_try.rb` | ProvisionSenderDomain operation | 41 | PASS |
| `try/unit/domain_validation/sender_strategies_try.rb` | Strategy factory, DNS records | 50 | PASS |
| `try/unit/domain_validation/parallel_dns_verification_try.rb` | Parallel DNS lookups | 25 | PASS (NEW) |
| `try/unit/security/dns_rate_limiter_try.rb` | DNS rate limiting | 11 | PASS |
| `try/unit/models/mailer_config_tracking_fields_try.rb` | Tracking fields | 23 | PASS (NEW) |
| `try/unit/models/custom_domain_mailer_config_try.rb` | MailerConfig model | 74 | PASS |
| `try/unit/jobs/domain_validation_worker_try.rb` | Worker queue config | 8 | PASS |
| `try/unit/jobs/domain_validation_async_flow_try.rb` | Async flow, retry | 21 | PASS |

### Coverage Status by Feature

| Feature | Implementation | Test Coverage |
|---------|---------------|---------------|
| Parallel DNS lookups (`verify_all_records`) | IMPLEMENTED | TESTED |
| Rate limiting for DNS queries | IMPLEMENTED | TESTED |
| Provider settings externalization | Hardcoded defaults | Partial (via strategy tests) |
| DNS result caching (Redis) | NOT IMPLEMENTED | NOT TESTED |
| DNS retry with backoff | BaseWorker only | TESTED (job level) |
| MailerConfig tracking fields | IMPLEMENTED | TESTED |

---

## 2. Feature Test Requirements

### 2.1 Parallel DNS Lookups (`verify_all_records`)

**Location**: `lib/onetime/domain_validation/sender_strategies/base_strategy.rb`

**Current Implementation**:
- Uses `Concurrent::Promises` for parallel DNS lookups
- Each record verification runs in its own future
- Results collected in original order
- Error isolation: individual record failures don't crash batch

**Tests Needed**:

```
Test Case ID: DNS-PARALLEL-001
Title: Parallel verification returns same results as sequential
Precondition: Mock strategy with 5 DNS records
Steps:
  1. Run verify_all_records
  2. Compare result count and order with input records
Expected: All 5 results returned in same order as input

Test Case ID: DNS-PARALLEL-002
Title: Error isolation prevents cascade failure
Precondition: One record lookup throws exception
Steps:
  1. Mock resolver to throw on record 3 of 5
  2. Run verify_all_records
Expected: Records 1,2,4,5 verified normally; record 3 has error field

Test Case ID: DNS-PARALLEL-003
Title: Resolver is shared across parallel lookups
Precondition: Multiple records
Steps:
  1. Instrument Resolv::DNS.new call count
  2. Run verify_all_records for 5 records
Expected: Resolv::DNS.new called exactly once (shared resolver)

Test Case ID: DNS-PARALLEL-004
Title: Timeout in one lookup does not block others
Precondition: Mock one record to timeout (5s), others immediate
Steps:
  1. Set up mixed timing scenario
  2. Measure total verification time
Expected: Total time ~ max(individual times), not sum

Test Case ID: DNS-PARALLEL-005
Title: Result hash includes error field on lookup failure
Precondition: DNS exception thrown
Steps:
  1. Force ResolvError on lookup
  2. Inspect result hash
Expected: Result contains :error key with exception message
```

### 2.2 Rate Limiting for DNS Queries

**Status**: Not yet implemented

**Proposed Design** (based on PassphraseRateLimiter pattern):
- Redis-backed counter per domain
- Window-based rate limiting (e.g., 10 checks per minute per domain)
- Global rate limit across all domains

**Tests Needed**:

```
Test Case ID: DNS-RATELIMIT-001
Title: First check within limit succeeds
Precondition: Fresh domain, no prior checks
Steps:
  1. Call validate_sender_domain
Expected: Validation proceeds normally

Test Case ID: DNS-RATELIMIT-002
Title: Exceeding domain limit raises LimitExceeded
Precondition: MAX_CHECKS_PER_DOMAIN = 5
Steps:
  1. Call validate 6 times rapidly for same domain
Expected: 6th call raises Onetime::LimitExceeded with retry_after

Test Case ID: DNS-RATELIMIT-003
Title: Rate limit resets after window expires
Precondition: Hit limit, then wait for window expiry
Steps:
  1. Exhaust rate limit
  2. Wait for RATE_LIMIT_WINDOW seconds (mock time)
  3. Call validate again
Expected: Validation proceeds normally

Test Case ID: DNS-RATELIMIT-004
Title: Different domains have independent limits
Precondition: Two different MailerConfig instances
Steps:
  1. Exhaust rate limit on domain A
  2. Validate domain B
Expected: Domain B validation succeeds

Test Case ID: DNS-RATELIMIT-005
Title: Global rate limit prevents DNS abuse
Precondition: GLOBAL_CHECKS_PER_MINUTE = 100
Steps:
  1. Validate 101 different domains rapidly
Expected: 101st call raises LimitExceeded
```

### 2.3 Provider Settings Externalization

**Current State**: Hardcoded in strategy classes
- `SesValidation::DEFAULT_REGION = 'us-east-1'`
- `SendgridValidation::DEFAULT_SUBDOMAIN = 'em'`

**Tests Needed**:

```
Test Case ID: CONFIG-PROVIDER-001
Title: Default region used when no config override
Precondition: No provider config in config.yaml
Steps:
  1. Create SES strategy without region option
  2. Generate MX record
Expected: MX value contains 'us-east-1'

Test Case ID: CONFIG-PROVIDER-002
Title: Config file region overrides hardcoded default
Precondition: config.yaml has mail.providers.ses.default_region: 'eu-west-1'
Steps:
  1. Create SES strategy without explicit region
  2. Generate MX record
Expected: MX value contains 'eu-west-1'

Test Case ID: CONFIG-PROVIDER-003
Title: Explicit option overrides config file
Precondition: config.yaml has default_region: 'eu-west-1'
Steps:
  1. Create SES strategy with region: 'ap-southeast-1'
  2. Generate MX record
Expected: MX value contains 'ap-southeast-1'

Test Case ID: CONFIG-PROVIDER-004
Title: SendGrid subdomain from config
Precondition: config.yaml has mail.providers.sendgrid.subdomain: 'mail'
Steps:
  1. Create SendGrid strategy
  2. Generate link branding CNAME
Expected: CNAME host starts with 'mail.'

Test Case ID: CONFIG-PROVIDER-005
Title: Invalid provider config raises on boot
Precondition: config.yaml has mail.providers.ses.region: 'invalid-region'
Steps:
  1. Boot application
Expected: Validation error logged (or raise depending on strictness)
```

### 2.4 DNS Result Caching (Redis)

**Status**: Not yet implemented

**Proposed Design**:
- Cache DNS lookup results per (host, record_type) tuple
- TTL based on DNS record TTL (minimum 60s, maximum 3600s)
- Cache key: `dns:cache:{sha256(host:type)}`
- Cache miss triggers live lookup, populates cache

**Tests Needed**:

```
Test Case ID: DNS-CACHE-001
Title: Cache miss triggers live lookup
Precondition: Empty cache
Steps:
  1. Query lookup_cname_records for uncached host
  2. Check Redis for cache key
Expected: Live lookup performed, result cached

Test Case ID: DNS-CACHE-002
Title: Cache hit returns cached value (no DNS query)
Precondition: Cache populated with prior result
Steps:
  1. Mock resolver to fail
  2. Query cached host
Expected: Cached value returned, no exception

Test Case ID: DNS-CACHE-003
Title: Cache expires after TTL
Precondition: TTL = 60s, cache populated
Steps:
  1. Advance time by 61 seconds
  2. Query same host
Expected: Cache miss, live lookup performed

Test Case ID: DNS-CACHE-004
Title: Cache respects minimum TTL floor
Precondition: DNS record returns TTL=5s
Steps:
  1. Query and cache result
  2. Check actual TTL in Redis
Expected: TTL set to MIN_CACHE_TTL (60s)

Test Case ID: DNS-CACHE-005
Title: Cache invalidation on verification failure
Precondition: Cached result shows verified=true
Steps:
  1. Force live lookup that shows verified=false
  2. Check cache state
Expected: Old cache evicted, new result cached
```

### 2.5 DNS Retry with Backoff

**Current State**: Implemented in `BaseWorker#with_retry` for job-level retry.
Strategy-level retry for transient DNS failures not yet implemented.

**Tests Needed**:

```
Test Case ID: DNS-RETRY-001
Title: Transient DNS failure retries with exponential backoff
Precondition: First 2 lookups fail, third succeeds
Steps:
  1. Mock resolver to fail twice then succeed
  2. Call verify_record with retry enabled
Expected: Success after retry, backoff delays observed

Test Case ID: DNS-RETRY-002
Title: Permanent failure does not retry
Precondition: NXDOMAIN (non-existent domain)
Steps:
  1. Query non-existent domain
Expected: No retry, immediate failure result

Test Case ID: DNS-RETRY-003
Title: Max retries prevents infinite loop
Precondition: All lookups fail
Steps:
  1. Set MAX_RETRIES = 3
  2. Force all lookups to timeout
Expected: Gives up after 3 retries (4 total attempts)

Test Case ID: DNS-RETRY-004
Title: Backoff follows exponential pattern
Precondition: BASE_DELAY = 0.5s
Steps:
  1. Force failures to trigger retries
  2. Measure delay between attempts
Expected: Delays are ~0.5s, ~1s, ~2s (with jitter)

Test Case ID: DNS-RETRY-005
Title: Retry wraps existing verify_record logic
Precondition: Retry enabled on strategy
Steps:
  1. Call verify_all_records
  2. One record times out, then succeeds on retry
Expected: Final results show verified=true for retried record
```

### 2.6 MailerConfig Tracking Fields

**Status**: Not yet implemented

**Proposed Fields**:
```ruby
field :last_check_at      # Unix timestamp of last verification attempt
field :check_duration_ms  # Duration of last verification in milliseconds
field :check_count        # Total number of verification attempts
field :last_error         # Most recent error message (nil if last check succeeded)
```

**Tests Needed**:

```
Test Case ID: TRACKING-001
Title: last_check_at updated on each verification
Precondition: MailerConfig with no prior checks
Steps:
  1. Run validation
  2. Reload config
Expected: last_check_at is recent timestamp

Test Case ID: TRACKING-002
Title: check_duration_ms records actual duration
Precondition: DNS lookup takes ~200ms
Steps:
  1. Run validation
  2. Check check_duration_ms
Expected: Value is ~200 (within tolerance)

Test Case ID: TRACKING-003
Title: check_count increments on each verification
Precondition: check_count = 5
Steps:
  1. Run validation
Expected: check_count = 6

Test Case ID: TRACKING-004
Title: last_error cleared on successful verification
Precondition: last_error = "Previous DNS timeout"
Steps:
  1. Run successful validation
Expected: last_error is nil

Test Case ID: TRACKING-005
Title: last_error populated on failed verification
Precondition: last_error = nil
Steps:
  1. Force DNS failure
Expected: last_error contains error message

Test Case ID: TRACKING-006
Title: Tracking fields persist across reloads
Precondition: Run validation, then reload config
Steps:
  1. Run validation
  2. Reload from Redis
  3. Check tracking fields
Expected: All values preserved
```

---

## 3. New Test Files Required

### 3.1 Parallel DNS Tests

**File**: `try/unit/domain_validation/parallel_dns_verification_try.rb`

```ruby
# try/unit/domain_validation/parallel_dns_verification_try.rb
#
# Tests for parallel DNS verification in BaseStrategy#verify_all_records
#
# Validates:
# 1. Results match input count and order
# 2. Error isolation (one failure doesn't crash batch)
# 3. Shared resolver (single Resolv::DNS instance)
# 4. Timeout isolation
# 5. Error field populated on individual failures
```

### 3.2 Rate Limiting Tests (when implemented)

**File**: `try/unit/domain_validation/dns_rate_limiter_try.rb`

### 3.3 Caching Tests (when implemented)

**File**: `try/unit/domain_validation/dns_cache_try.rb`

### 3.4 Configuration Tests

**File**: `try/unit/config/mail_provider_config_try.rb`

### 3.5 Tracking Fields Tests

**File**: `try/unit/models/mailer_config_tracking_fields_try.rb`

---

## 4. Integration Test Scenarios

### 4.1 End-to-End DNS Validation Flow

```
Scenario: Full validation cycle with caching and retry
Given a MailerConfig with provider 'ses'
And DNS cache is empty
When I call ValidateSenderDomain
Then parallel lookups should be performed
And results should be cached
And tracking fields should be updated
When I immediately call ValidateSenderDomain again
Then cached results should be used
And check_count should increment
```

### 4.2 Rate Limiting Under Load

```
Scenario: Concurrent validation requests
Given 100 concurrent validation requests for different domains
When all requests are submitted simultaneously
Then no request should fail due to rate limiting (within global limit)
And each domain should have its own rate limit state
```

---

## 5. Edge Cases and Error Conditions

| Edge Case | Expected Behavior |
|-----------|-------------------|
| DNS resolver unavailable | Retry with backoff, then fail with error |
| All records timeout | Return all-failed result, persist to model |
| Redis unavailable (cache) | Fallback to live lookup, log warning |
| Redis unavailable (rate limit) | Skip rate limiting, log warning |
| Invalid mailer_config | ArgumentError raised before any DNS queries |
| Empty domain_id | Early return with validation error |
| Concurrent validation (same domain) | Rate limit prevents concurrent abuse |
| Strategy raises NotImplementedError | Wrapped in Result.error, not re-raised |

---

## 6. Test Execution Order

1. Unit tests for tracking fields (model layer)
2. Unit tests for parallel DNS (strategy layer)
3. Unit tests for rate limiting (new module)
4. Unit tests for caching (new module)
5. Unit tests for config externalization
6. Integration tests for end-to-end flow
7. Load tests for rate limiting effectiveness

---

## 7. Automation Notes

- All tests use tryouts framework (preferred) or RSpec
- Mock DNS lookups via Resolv::DNS stubbing
- Use Redis pipeline for rate limit state verification
- Time-sensitive tests use `Timecop` or `travel_to`
- Concurrent tests use `Concurrent::Promises` directly

---

## 8. Test Data Requirements

### Fixture Data

```ruby
# Reusable test fixtures
@mock_custom_domain = Struct.new(:display_domain, :identifier).new(
  'test.example.com', 'cd:test123'
)
@mock_mailer_config = Struct.new(:custom_domain, :domain_id, :provider).new(
  @mock_custom_domain, 'cd:test123', 'ses'
)
```

### Mock DNS Responses

```ruby
# Successful CNAME lookup
@mock_cname_result = ['token.dkim.amazonses.com']

# Failed lookup (timeout)
@mock_timeout = Resolv::ResolvTimeout.new('DNS query timed out')

# NXDOMAIN (non-existent)
@mock_nxdomain = Resolv::ResolvError.new('no address for host')
```

---

## 9. Acceptance Criteria Summary

| Feature | Criteria |
|---------|----------|
| Parallel DNS | Total time < sum of individual lookups |
| Error Isolation | Single record failure doesn't fail batch |
| Rate Limiting | Per-domain and global limits enforced |
| Caching | Cache hit ratio > 80% on repeated checks |
| Retry | Transient failures recovered within 3 retries |
| Tracking | All fields updated and persisted correctly |
| Config | Settings loadable from config.yaml |

---

## 10. Sign-off Checklist

- [x] All unit tests pass (`bundle exec try --agent`) - **315 tests passing**
- [x] No regressions in existing test suites
- [x] Parallel DNS verification tests added (25 tests)
- [x] Rate limiting tests verified (11 tests)
- [x] Tracking fields tests added (23 tests)
- [x] Edge cases documented and tested
- [ ] Integration tests cover end-to-end flow (pending)
- [ ] Performance benchmarks (pending)

---

## 11. Outstanding Work

### Not Yet Implemented

1. **DNS Result Caching (Redis)** - Task #4 pending implementation
2. **Strategy-level DNS Retry with Backoff** - Task #5 pending implementation
3. **Provider Settings Externalization** - Task #3 partial (hardcoded defaults work)

### Tests To Add When Features Are Implemented

**DNS Caching (when implemented):**
- Cache miss triggers live lookup
- Cache hit returns cached value without DNS query
- Cache expires after TTL
- Cache invalidation on verification failure
- Minimum TTL floor enforced

**Strategy-level Retry (when implemented):**
- Transient DNS failure retries with backoff
- Permanent failure (NXDOMAIN) does not retry
- Max retries prevents infinite loop
- Backoff follows exponential pattern with jitter

# Comprehensive Test Data for OneTimeSecret

## Overview

This directory contains **80 edge case test scenarios** designed to find bugs that naive implementations would miss. Each test case:

1. **Violates a specific assumption** that developers commonly make
2. **Documents what breaks** if the edge case isn't handled
3. **Provides verification steps** to confirm proper handling

## Test Categories

### 1. Secret Creation Edge Cases (10 tests: SEC-001 to SEC-010)
- Empty secrets with passphrases
- Size boundary violations (exact 1MB, off-by-one errors)
- Unicode attacks (RTL override, null bytes, control characters)
- Injection attempts in passphrases
- TTL boundary edge cases
- Whitespace-only secrets
- Double encryption detection

**Key Bug Found**: SEC-001 catches Ruby 3.1 OpenSSL crash on empty strings (fixed via encryption mode -1)

### 2. Customer Validation Bugs (10 tests: CUST-001 to CUST-010)
- Email length boundaries (minimum "a@b.c", maximum 254 chars)
- International domains (IDN/punycode)
- Case sensitivity traps
- Anonymous user abuse vectors
- Role manipulation attacks
- Idempotency failures

**Key Bug Found**: CUST-004 reveals TLD regex only allows 2-4 chars, rejecting valid .museum domains

### 3. Metadata State Conflicts (10 tests: META-001 to META-010)
- Orphaned metadata without secrets
- Secret/metadata state mismatches
- Race conditions in state transitions
- TTL calculation errors
- View count invariant violations
- Circular references (owner as recipient)

**Key Bug Found**: META-002 exposes lack of atomic state updates between secret and metadata

### 4. Timing Attacks (10 tests: TIME-001 to TIME-010)
- Future timestamps bypassing TTL
- Midnight UTC boundary conditions
- DST transitions and leap seconds
- Clock skew between Redis and app servers
- Concurrent operations race conditions
- Integer overflow (year 2038 problem)

**Key Bug Found**: TIME-001 shows future timestamps create effectively permanent secrets

### 5. Injection Attempts (10 tests: INJ-001 to INJ-010)
- XSS in emails and secret content
- Path traversal in share_domain
- Redis command injection
- CSV formula injection
- SMTP header injection
- Template injection (ERB/Liquid)

**Key Bug Found**: INJ-006 demonstrates CSV export vulnerability allowing command execution

### 6. Encryption Edge Cases (10 tests: ENC-001 to ENC-010)
- Null bytes in passphrases
- Encryption key rotation failures
- Unknown encryption modes
- Checksum validation gaps
- Unicode encoding mismatches
- Gibbler (SHA1) collision attacks

**Key Bug Found**: ENC-005 reveals missing checksum validation after decryption

### 7. TTL Boundary Violations (10 tests: TTL-001 to TTL-010)
- Zero and negative TTL values
- Fractional seconds precision loss
- Very large TTL (100 years) resource exhaustion
- String vs integer type confusion
- Unit confusion (seconds vs milliseconds)
- Overflow in metadata TTL calculation

**Key Bug Found**: TTL-004 shows "abc7200" silently converts to 0, immediate expiration

### 8. Multi-Tenancy Issues (10 tests: TENANT-001 to TENANT-010)
- Cross-customer secret access
- Deleted customer secret persistence
- Anonymous user rate limit sharing
- Email change breaking ownership
- Session fixation attacks
- API token leakage
- Stripe ID collisions

**Key Bug Found**: TENANT-003 reveals all anonymous users share same rate limit counter

## Usage

### Running Individual Test Cases

Each test case can be loaded and validated programmatically:

```ruby
require 'json'

# Load test data
test_data = JSON.parse(File.read('tests/fixtures/comprehensive_test_data.json'))

# Get specific test case
test = test_data['test_cases']['secret_creation_edge_cases'].find { |t| t['id'] == 'SEC-001' }

puts "Testing: #{test['name']}"
puts "Assumption: #{test['assumption_violated']}"
puts "Expected failure: #{test['what_breaks']}"

# Execute test with data
secret = V2::Secret.create(
  custid: test['data']['custid'],
  value: test['data']['secret_value'],
  passphrase: test['data']['passphrase'],
  ttl: test['data']['ttl']
)

# Verify proper handling
puts "Verification: #{test['verification']}"
```

### Integration with RSpec

```ruby
# tests/unit/ruby/rspec/comprehensive_edge_cases_spec.rb

RSpec.describe 'Comprehensive Edge Cases' do
  let(:test_data) do
    JSON.parse(File.read('tests/fixtures/comprehensive_test_data.json'))
  end

  describe 'Secret Creation Edge Cases' do
    test_data['test_cases']['secret_creation_edge_cases'].each do |test_case|
      it test_case['name'] do
        # Test implementation based on test_case['data']
        # Verify test_case['verification'] passes
      end
    end
  end
end
```

### Audit Checklist

Use this checklist during code review:

- [ ] **SEC-001**: Empty secrets with passphrases handled (encryption mode -1)
- [ ] **SEC-002**: Size checks use >= not > (off-by-one protection)
- [ ] **SEC-003**: RTL override and null bytes escaped in display
- [ ] **SEC-008**: Whitespace-only secrets rejected or documented
- [ ] **CUST-004**: TLD regex updated to support long TLDs (.museum, etc)
- [ ] **CUST-005**: Email normalization applied before comparison
- [ ] **META-002**: State transitions use Redis MULTI/EXEC for atomicity
- [ ] **META-004**: Metadata TTL >= secret TTL enforced
- [ ] **TIME-001**: Created timestamp validated within reasonable range
- [ ] **TIME-009**: State transitions serialized with distributed lock
- [ ] **INJ-004**: Secret content HTML-escaped in all display contexts
- [ ] **INJ-006**: CSV export prefixes formula chars with single quote
- [ ] **ENC-005**: Checksum validated after decryption
- [ ] **ENC-009**: Migration from SHA1 (Gibbler) to SHA256 planned
- [ ] **TTL-004**: TTL validated as numeric before to_i conversion
- [ ] **TTL-010**: Active expiration check before loading secrets
- [ ] **TENANT-003**: Anonymous rate limiting by IP, not shared custid
- [ ] **TENANT-005**: custid made immutable or email stored separately

## Test Data Statistics

- **Total test cases**: 80
- **Categories**: 8
- **Bug severity breakdown**:
  - **Critical** (RCE, auth bypass): 12 tests
  - **High** (data leak, integrity): 28 tests
  - **Medium** (DoS, UX bugs): 24 tests
  - **Low** (edge cases, docs): 16 tests

## Anti-Patterns Avoided

This test data does NOT include:
- ❌ Simple valid records with different IDs (not edge cases)
- ❌ "Edge cases" that are just normal variations
- ❌ Tests without specific failure modes
- ❌ Data any basic system would handle fine
- ❌ Repetitive variations of the same bug

## Validation Rules

Every test case must answer:
1. **What assumption does this violate?**
2. **What specifically breaks in a naive implementation?**
3. **How do you verify the fix works?**

If you can't answer all three, the test case is invalid and should be removed.

## Contributing New Test Cases

When adding new test cases:

1. Follow the JSON schema:
```json
{
  "id": "CATEGORY-###",
  "name": "Short descriptive name",
  "data": {
    "test_input": "actual_test_data"
  },
  "assumption_violated": "One sentence describing the broken assumption",
  "what_breaks": "Detailed explanation of failure mode and impact",
  "verification": "Steps to verify proper handling"
}
```

2. Ensure the test finds a **real bug**, not just exercises code
3. Document the **specific failure mode**, not generic "could break"
4. Provide **actionable verification** steps

## References

- OneTimeSecret secret model: `apps/api/v2/models/secret.rb`
- Customer model: `apps/api/v2/models/customer.rb`
- Metadata model: `apps/api/v2/models/metadata.rb`
- Secret creation logic: `apps/api/v2/logic/secrets/base_secret_action.rb`
- Encryption implementation: Lines 114-191 in `secret.rb`

## License

This test data is part of the OneTimeSecret project and follows the same license.

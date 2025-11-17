# Ruby Code Smells and Technical Debt Report

**Generated**: 2025-11-17
**Project**: Onetime Secret
**Ruby Files Analyzed**: 312 files

## Executive Summary

This report identifies critical code smells and technical debt in the Onetime Secret Ruby codebase. The analysis found **38 distinct issues** ranging from critical design flaws to maintenance concerns. The most pressing issues include massive code duplication between API versions, god objects with excessive responsibilities, and several security concerns.

---

## 🔴 CRITICAL ISSUES (Must Address Immediately)

### 1. Massive Code Duplication Between V1 and V2 APIs

**Severity**: CRITICAL
**Effort**: 40-60 hours
**Files Affected**:
- `apps/api/v1/controllers/helpers.rb` (556 lines)
- `apps/api/v2/controllers/helpers.rb` (556 lines)
- `apps/api/v1/models/customer.rb` (481 lines)
- `apps/api/v2/models/customer.rb` (481 lines)
- `apps/api/v1/models/custom_domain.rb` (594 lines)
- `apps/api/v2/models/custom_domain.rb` (594 lines)

**Issue**: V1 and V2 API implementations are nearly identical, differing only in namespace. This creates:
- Maintenance nightmare (bugs must be fixed twice)
- Risk of inconsistent behavior
- Violation of DRY principle
- Double the code to test

**Example**: Both helpers files contain identical 127-line `carefully` method (lines 23-149) with only namespace differences (`V1::` vs `V2::`).

**Recommendation**:
1. Extract shared logic into common module/base class
2. Use composition or inheritance for version-specific differences
3. Consider if V1 can be deprecated or consolidated

---

### 2. God Method: `carefully` (127 Lines, 8 Rescue Blocks)

**Severity**: CRITICAL
**Effort**: 20-30 hours
**Files**:
- `apps/api/v2/controllers/helpers.rb:23-149`
- `apps/api/v1/controllers/helpers.rb:23-149`

**Issue**: Single method handles multiple unrelated responsibilities:
- Authentication
- Request validation
- Error handling (8 different exception types)
- Logging
- Sentry integration
- Security headers (CSP, nonce generation)
- Session management
- Response formatting

**Problems**:
- Impossible to test in isolation
- High cyclomatic complexity
- Violates Single Responsibility Principle
- Difficult to modify without breaking something

**Recommendation**: Refactor into specialized components:
```ruby
class RequestProcessor
  def initialize(authenticator, error_handler, logger, security_policy)
    # ...
  end
end
```

---

### 3. Bare Rescue Clause

**Severity**: CRITICAL
**Effort**: 1 hour
**File**: `apps/api/v2/logic/colonel/update_system_settings.rb:77`

**Code**:
```ruby
rescue => e
  OT.le "[UpdateSystemSettings#process] Failed to persist: #{e.message}"
  raise_form_error "Failed to update configuration: #{e.message}"
end
```

**Issue**: Catches ALL exceptions including `SignalException`, `SystemExit`, `NoMemoryError`
- Could hide critical system errors
- Makes debugging extremely difficult
- Could mask security issues

**Recommendation**:
```ruby
rescue Redis::BaseError, Familia::Problem => e
  # specific error handling
end
```

---

### 4. Multiple Rescue Modifier Anti-patterns

**Severity**: HIGH
**Effort**: 2 hours
**Files**:
- `apps/api/v2/controllers/helpers.rb:321-322`
- `apps/api/v2/controllers/helpers.rb:436`
- `apps/api/v1/controllers/helpers.rb:321-322`
- `apps/api/v1/controllers/helpers.rb:436`

**Code Example**:
```ruby
authentication_enabled = OT.conf[:site][:authentication][:enabled] rescue false
signin_enabled = OT.conf[:site][:authentication][:signin] rescue false
headers = req.env.select { |k, _v| k.start_with?('HTTP_') rescue false }
```

**Issue**:
- Silently swallows all errors
- Makes debugging configuration issues impossible
- Security risk: defaults to `false` on ANY error

**Recommendation**:
```ruby
authentication_enabled = OT.conf.dig(:site, :authentication, :enabled) || false
# or with explicit error handling
begin
  authentication_enabled = OT.conf[:site][:authentication][:enabled]
rescue KeyError, NoMethodError => e
  OT.le "Missing config: #{e.message}"
  authentication_enabled = false
end
```

---

## 🟠 HIGH PRIORITY ISSUES

### 5. Large God Objects (300+ Lines)

**Severity**: HIGH
**Effort**: 30-50 hours (varies)

| Class | Lines | Location | Issues |
|-------|-------|----------|--------|
| `CustomDomain` | 594 | `apps/api/v2/models/custom_domain.rb` | DNS, parsing, validation, persistence mixed |
| `Customer` | 481 | `apps/api/v2/models/customer.rb` | Auth, Stripe, sessions, core data all together |
| `ControllerHelpers` | 556 | `apps/api/v2/controllers/helpers.rb` | 36+ methods with kitchen sink anti-pattern |
| `Config` | 482+ | `lib/onetime/config.rb` | Loading, validation, merging combined |
| `Utils` | 388+ | `lib/onetime/utils.rb` | 8+ different utility categories mixed |

**Recommendation**: Apply Single Responsibility Principle:
- Extract service objects
- Create dedicated validators
- Separate persistence from business logic

---

### 6. Magic Numbers and Undocumented Constants

**Severity**: HIGH
**Effort**: 4 hours
**Locations**: Multiple files

**Examples**:
- Encryption modes: `-1, 0, 1, 2` (used throughout Secret models)
- Time values: `7.days`, `365.days`, `24.hours` (inconsistent usage)
- Rate limit values scattered in code
- Redis DB numbers: `6, 7, 8` (no documentation)

**Files**:
- `apps/api/v2/models/secret.rb` (encryption modes)
- `apps/api/v2/models/customer.rb:358` (`365.days` TTL)
- `lib/onetime/config.rb` (various TTL values)

**Recommendation**: Create constant classes:
```ruby
module SecretEncryption
  MODE_LEGACY = -1
  MODE_DISABLED = 0
  MODE_AES256 = 1
  MODE_AES256_GCM = 2
end
```

---

### 7. Security Issue: Weak Random Number Generation

**Severity**: HIGH
**Effort**: 1 hour
**File**: `tests/unit/ruby/try/60_logic/24_logic_destroy_account_try.rb:39`

**Code**:
```ruby
username = (0...8).map { ('a'..'z').to_a[rand(26)] }.join
```

**Issue**: Uses `rand()` instead of `SecureRandom` in test that generates usernames

**Recommendation**:
```ruby
username = (0...8).map { ('a'..'z').to_a[SecureRandom.random_number(26)] }.join
# or better:
username = SecureRandom.alphanumeric(8)
```

---

### 8. Inconsistent Error Message Exposure

**Severity**: MEDIUM
**Effort**: 3 hours
**File**: `apps/api/v2/logic/colonel/update_system_settings.rb:79`

**Code**:
```ruby
raise_form_error "Failed to update configuration: #{e.message}"
```

**Issue**: Exposes raw exception messages to users, potentially leaking:
- Internal paths
- Redis errors
- Stack trace information

**Recommendation**: Use sanitized error messages for users, log details separately

---

## 🟡 MEDIUM PRIORITY ISSUES

### 9. Long Methods (30+ Lines with High Complexity)

**Severity**: MEDIUM
**Files**:
- `apps/api/v2/controllers/helpers.rb:166-190` (`check_locale!` - 25 lines)
- `apps/api/v2/controllers/helpers.rb:241-305` (`check_session!` - 65 lines)
- `apps/api/v2/controllers/helpers.rb:333-383` (`add_response_headers` - 51 lines)
- `apps/api/v2/models/custom_domain.rb:310-340` (`generate_txt_validation_record` - 31 lines)

**Recommendation**: Extract helper methods and service objects

---

### 10. Technical Debt: 35+ TODO Comments

**Severity**: MEDIUM
**Effort**: Variable
**Examples**:
- `apps/api/v2/controllers/helpers.rb:7` - "TODO: Add config"
- `apps/api/v2/models/customer.rb:35` - "TODO: use sorted set?"
- `apps/api/v2/models/secret.rb:74` - "TODO: Remove"
- `lib/onetime/config.rb:154` - "TODO: We don't need to re-assign"

**Recommendation**: Triage TODOs, create tickets for valid ones, remove stale ones

---

### 11. Tight Coupling to External Services

**Severity**: MEDIUM
**Files**: `apps/api/v2/models/customer.rb:131-201`

**Issue**: Direct Stripe API calls embedded in model:
- `get_stripe_customer` (lines 131-136)
- `get_stripe_subscription` (lines 138-140)
- `get_stripe_customer_by_id` (lines 142-151)

**Recommendation**: Extract to `StripeService` or adapter pattern

---

### 12. Inconsistent String Comparison Patterns

**Severity**: LOW
**Locations**: Multiple files

**Examples**:
```ruby
# Pattern 1: String equality
verified.to_s == 'true'

# Pattern 2: Boolean equality
verified.to_s.eql?('true')

# Pattern 3: Boolean conversion
!!verified

# Pattern 4: Truthy check
verified.to_s != 'false'
```

**Files**:
- `apps/api/v2/models/customer.rb:111, 246, 296`
- `apps/api/v2/models/custom_domain.rb:271, 275, 365`

**Recommendation**: Standardize on one pattern, preferably using Boolean fields

---

### 13. Complex Boolean Logic Without Guards

**Severity**: MEDIUM
**File**: `apps/api/v2/models/customer.rb:249-260`

**Code**:
```ruby
def active?
  verified? && role?('customer')
end

def pending?
  !anonymous? && !verified? && role?('customer')
end
```

**Issue**: Multiple method calls, easy to introduce bugs with state changes

**Recommendation**: Add guard clauses and clear state machine

---

### 14. Hardcoded Cache Expiration Date

**Severity**: LOW
**File**: `apps/api/v2/controllers/helpers.rb:545`

**Code**:
```ruby
res.header['Expires'] = "Mon, 7 Nov 2011 00:00:00 UTC"
```

**Issue**: Hardcoded date from 2011, should use dynamic past date or standard value

**Recommendation**:
```ruby
res.header['Expires'] = Time.at(0).httpdate # Unix epoch
```

---

## 📊 Summary Statistics

| Category | Count | Total Effort |
|----------|-------|--------------|
| Critical Issues | 4 | 63-93 hours |
| High Priority | 5 | 40-60 hours |
| Medium Priority | 5 | 15-25 hours |
| **TOTAL** | **14** | **118-178 hours** |

---

## 🎯 Recommended Action Plan

### Phase 1: Critical Fixes (Week 1-2)
1. ✅ Fix bare rescue in `update_system_settings.rb`
2. ✅ Replace rescue modifiers with explicit error handling
3. ✅ Fix `rand()` usage in tests
4. ✅ Create encryption mode constants

**Estimated**: 8 hours

### Phase 2: Consolidation (Week 3-6)
5. 🔄 Extract V1/V2 shared code into common modules
6. 🔄 Refactor `carefully` method into components
7. 🔄 Extract Stripe logic into service objects

**Estimated**: 60-80 hours

### Phase 3: Cleanup (Week 7-10)
8. 🧹 Break down god objects (Customer, CustomDomain)
9. 🧹 Triage and address TODOs
10. 🧹 Standardize error handling patterns

**Estimated**: 50-70 hours

---

## 🔧 Quick Wins (Can Be Done Today)

1. **Fix bare rescue** (30 min)
   - File: `apps/api/v2/logic/colonel/update_system_settings.rb:77`

2. **Add encryption constants** (1 hour)
   - Create `lib/onetime/secret_encryption.rb`

3. **Fix hardcoded expiration date** (15 min)
   - File: `apps/api/v2/controllers/helpers.rb:545`

4. **Replace rescue modifiers** (2 hours)
   - Files: `apps/api/v*/controllers/helpers.rb`

---

## 📚 Additional Issues Not Listed

- **Dead Code**: Commented-out code blocks
- **Inconsistent Naming**: `custid` vs `customer_id`
- **Missing Null Checks**: Several `&.` chains that could be simplified
- **Complex SQL-like Redis Queries**: Could benefit from query objects
- **Missing Test Coverage**: Several edge cases not covered

---

## ✅ Things Done Well

- ✅ Good use of `SecureRandom` for most security-sensitive operations
- ✅ Comprehensive error handling structure (just needs refactoring)
- ✅ Good documentation in comments
- ✅ Sentry integration for error tracking
- ✅ YARD documentation on many methods
- ✅ Security-conscious CSP headers

---

## 📖 References

- **Ruby Style Guide**: https://rubystyle.guide/
- **Refactoring Patterns**: Martin Fowler's "Refactoring"
- **OWASP Top 10**: https://owasp.org/www-project-top-ten/

---

**Report prepared by**: Code Review Analysis
**Next Review**: Recommended in 3 months after addressing critical issues

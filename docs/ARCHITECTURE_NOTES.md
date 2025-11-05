# Architecture Notes - Test Fixes & API v3 Migration

## Current Branch: fix/test-failures-api-updates

### Completed Work

#### Ruby/Backend Tests (Commit 12f54e0cc)
- ✅ 405 passing (up from 319) - 27% improvement
- ✅ Fixed Familia v2 API migration (`.redis` → `.dbclient`)
- ✅ Created missing config files (logging.yaml, auth.yaml, config.yaml)
- ✅ Renamed `LegacyEncryptedFields::spawn_pair` to `legacy_spawn_pair`
- ✅ Fixed middleware keyword arguments (`io:` → `logger:`)
- ✅ Added missing `strategy_name` to `StrategyResult`
- ✅ Fixed syntax errors and nil references
- ✅ Documented remaining failures in [Issue #1865](https://github.com/onetimesecret/onetimesecret/issues/1865)

### API v2 → v3 Migration Strategy

**Key Insight:** The transition from string-based (v2) to JSON-typed (v3) responses is an architectural change that requires versioning, not just updates.

**v2 API** - Maintain for backward compatibility:
- All primitives as strings (Redis legacy)
- Endpoints: `/api/v2/*`
- Schemas: String-based with Zod transformations

**v3 API** - Active development:
- Proper JSON types (number, boolean, null, string)
- Endpoints: `/api/v3/*`
- Schemas: Current Zod schemas expecting typed values

**Implementation Needed:**
1. Backend: Duplicate routes for v2/v3 with different serialization
2. Frontend: Maintain v2 schemas alongside v3
3. Migration: Deprecation timeline for v2

See `/tmp/api-v3-strategy.md` for full details.

### MFA Security Error Messages

**Security Review:** Current error messages leak information that aids attackers.

**Key Changes Needed:**
- ❌ "Incorrect password" → ✅ "Authentication failed"
- ❌ "Wait 5 minutes" → ✅ "Try again later"
- ✅ Keep recovery code messages (already secure)

See `/tmp/mfa-error-security.md` for complete analysis.

### Vue/Frontend Test Failures

**Current State:**
- 50 tests failing / 368 passing
- Main issues: Error message format, date validation, error classification

**Root Causes:**
1. Tests expect v2 string format, code uses v3 types
2. MFA error messages need security hardening
3. Date parsing needs ISO 8601 → Date transformation

**Resolution Path:**
1. Implement v2/v3 API split
2. Update MFA error messages per security guidelines
3. Update tests to match secure patterns
4. Fix date transformation for v3 API

## Next Steps

### Option A: Complete v3 Migration First
1. Create `/apps/api/v3/` directory structure
2. Implement typed JSON serialization
3. Update frontend to use v3 endpoints
4. Fix remaining test failures

### Option B: Fix Tests Within Current Structure
1. Apply MFA security error message fixes
2. Update tests to match secure patterns
3. Fix date validation issues
4. Defer v2/v3 split to separate PR

### Option C: Hybrid Approach
1. Fix critical security issues in MFA errors (high priority)
2. Document v2/v3 strategy (done)
3. Create separate issues for:
   - [NEW] Implement API v3 architecture
   - [NEW] Update MFA tests for secure error messages
   - [#1865] Complete remaining Ruby test fixes

## Recommendations

I recommend **Option C** - the hybrid approach:

**Immediate (this PR):**
- Commit Ruby test fixes ✅
- Document API v3 strategy ✅
- Document MFA security recommendations ✅
- Create tracking issues for v3 implementation

**Follow-up PRs:**
- API v3 implementation (backend + frontend)
- MFA security hardening + test updates
- Complete Ruby test suite fixes

This approach delivers incremental value while properly scoping the architectural work.

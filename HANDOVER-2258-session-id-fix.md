# Dev Handover: Issue #2258 - Session ID Fix

## Status: MOSTLY COMPLETE

### Original Issue - FIXED
**Commit 918892cbe**: Fixed `session.id` NoMethodError when session is a Hash fallback.

Changed 4 locations to use `session[:session_id]` instead of `session.id`:
- `lib/middleware/session_spanner.rb:71`
- `apps/web/core/serializers/hydration_scope.rb:46, 125, 195`

### CI Infrastructure Fixes Applied

| Commit | Description |
|--------|-------------|
| 94b5a2a47 | Changed table_guard_sequel_mode from :create to :log |
| de2d2c30f | Use file-based SQLite (`sqlite:///tmp/auth_test.db`) in CI |
| 4820a7e0c | Respect AUTH_DATABASE_URL env var in rake spec tasks |
| 32d7cb429 | Use AUTH_DATABASE_URL in FullModeSuiteDatabase |
| b75a05baf | Fix I18n configuration in rhales_migration_spec.rb |
| 3758e1240 | Fix I18n configuration in auth_mode_spec.rb |
| 89ab9f429 | Add OT locale settings to auth_mode_spec.rb |

### Current CI Status (run 20518704087 pending)

**PASSING:**
- Full Mode - SQLite (was 75 failures → 0)
- Full Mode - PostgreSQL
- Ruby/TypeScript Unit Tests
- Linting

**PENDING FIX (commit 89ab9f429):**
- Simple Mode: 4 failures in `auth_mode_spec.rb` - missing OT.supported_locales/default_locale

**REMAINING (Pre-existing, unrelated to #2258):**
- Disabled Mode: 20 failures
  - `entitlement_test_spec.rb` - Colonel API tests
  - `default_workspace_creation_spec.rb` - Organization membership issues

## Disabled Mode Failures - Next Steps

These are **pre-existing test issues**, not caused by #2258:

1. **Workspace Creation Tests** (`spec/integration/all/default_workspace_creation_spec.rb`):
   - `@org.member?(@customer)` returns false
   - `customer_orgs.size` returns 0 instead of 1
   - Root cause: `Organization.create!` calls `add_members_instance` but membership not persisting

2. **Entitlement Tests** (`spec/integration/all/entitlement_test_spec.rb`):
   - Colonel API tests for entitlement-test endpoint
   - Issues with nil organization handling, Thread.current middleware

**Recommendation**: File separate issues for Disabled Mode failures - they're test infrastructure issues unrelated to session.id fix.

## Branch
`fix/2258-rspec-wrongscope`

## PR
https://github.com/onetimesecret/onetimesecret/pull/2262

## Key Files Modified
- `lib/middleware/session_spanner.rb`
- `apps/web/core/serializers/hydration_scope.rb`
- `apps/web/auth/config/base.rb`
- `.github/workflows/ci.yml`
- `lib/tasks/spec.rake`
- `spec/support/full_mode_suite_database.rb`
- `spec/integration/simple/rhales_migration_spec.rb`
- `spec/integration/simple/auth_mode_spec.rb`

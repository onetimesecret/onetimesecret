# Billing Terminology Migration - Implementation Plan
**Date**: 2025-01-20
**Branch**: claude/working-branch-name
**Target Branch**: develop
**Status**: Ready for Implementation

## Executive Summary

This plan implements the approved **Plan/Plans/Catalog** terminology resolution to fix critical bugs and eliminate semantic confusion in the billing system.

**Key Changes:**
- `CatalogCache` → `Plan` (class rename)
- `catalog_id` → `plan_id` (field rename)
- `list_catalogs` → `list_plans` (method rename)
- Organization `planid` → `plan_id` (standardize foreign key convention)
- Create new `Catalog` class for collection-level operations

---

## Critical Bugs Found

### 🔴 Production-Breaking Bugs

1. **apps/web/billing/cli/helpers.rb:69**
   ```ruby
   plan.plan_id[0..19]  # ❌ NoMethodError - field is 'catalog_id'
   ```

2. **apps/web/billing/controllers/billing.rb:257**
   ```ruby
   id: plan.plan_id,  # ❌ NoMethodError - field is 'catalog_id'
   ```

3. **lib/onetime/billing/catalog_definitions.rb:54, 124**
   ```ruby
   ::Billing::Models::CatalogCache.list_catalog  # ❌ NoMethodError - method is 'list_catalogs'
   ```

4. **apps/web/billing/controllers/plans.rb:62, 79**
   ```ruby
   catalog = get_catalog(...)
   plan.stripe_price_id  # ❌ NameError - variable is 'catalog', not 'plan'
   ```

5. **apps/web/billing/controllers/billing.rb:92**
   ```ruby
   catalog = get_catalog(...)
   plan.stripe_price_id  # ❌ NameError - variable is 'catalog', not 'plan'
   ```

6. **try/billing/01_catalog_cache_try.rb:72**
   ```ruby
   @yearly_catalog.save  # ❌ NameError - variable is '@yearly_plan'
   ```

---

## File Impact Analysis

### Files to Rename

| Current Path | New Path | Reason |
|--------------|----------|--------|
| `apps/web/billing/models/catalog_cache.rb` | `apps/web/billing/models/plan.rb` | Rename model |
| `lib/onetime/billing/catalog_definitions.rb` | `lib/onetime/billing/plan_definitions.rb` | Align with new terminology |
| `try/billing/01_catalog_cache_try.rb` | `try/billing/01_plan_try.rb` | Align with new model name |

### Files with Critical Changes (Bugs to Fix)

| File | Lines | Changes | Bug Type |
|------|-------|---------|----------|
| `apps/web/billing/cli/helpers.rb` | 69 | `plan.plan_id` → already correct (field was wrong) | Field access |
| `apps/web/billing/controllers/billing.rb` | 92, 103, 206, 257 | Fix variable names and field access | Mixed |
| `apps/web/billing/controllers/plans.rb` | 39, 62, 79 | Fix variable names | Variable naming |
| `lib/onetime/billing/catalog_definitions.rb` | 54, 67, 85, 124, 125 | Method and field renames | Method name |
| `try/billing/01_catalog_cache_try.rb` | 20, 21, 55, 60, 72, 74 | Fix parameters and variable names | Test consistency |

### Files with Moderate Changes

| File | Changes | Count |
|------|---------|-------|
| `apps/web/billing/controllers/capabilities.rb` | Update field access, method calls | ~5 |
| `lib/onetime/models/organization.rb` | Add `plan_id` field (keep `planid` for backwards compat) | 2 |
| `lib/onetime/models/customer.rb` | Add `plan_id` field (keep `planid` for backwards compat) | 2 |
| `lib/onetime/models/organization/features/with_organization_billing.rb` | Update to use `plan_id` | ~10 |

### New Files to Create

| File | Purpose |
|------|---------|
| `lib/onetime/billing/catalog.rb` | New Catalog class for collection operations |

---

## Phase-by-Phase Implementation

### Phase 1: Model Core Migration
**Objective**: Rename primary model and core fields
**Risk**: Low (isolated changes)
**Estimated Time**: 2 hours

#### Tasks:

1.1. **Rename model file**
   - Move `apps/web/billing/models/catalog_cache.rb` → `plan.rb`
   - Update class name: `CatalogCache` → `Plan`
   - Update prefix: `:billing_catalog` → `:billing_plan`

1.2. **Update model fields**
   - Change `identifier_field :catalog_id` → `:plan_id`
   - Change `field :catalog_id` → `:plan_id`
   - Update all internal references to `catalog_id` → `plan_id`
   - Update comments referencing "catalog"

1.3. **Update model methods**
   - Rename `list_catalogs` → `list_plans`
   - Rename `get_catalog` → `get_plan`
   - Rename `clear_cache` → `clear_plans_cache`

1.4. **Update model require paths**
   - Update `require_relative` statements in controllers
   - Update require in `lib/onetime/billing/catalog_definitions.rb`

**Files Changed**: 1 file

---

### Phase 2: Fix Critical Bugs
**Objective**: Fix all production-breaking bugs
**Risk**: Low (direct fixes)
**Estimated Time**: 1 hour

#### Tasks:

2.1. **Fix helpers.rb:69**
   ```ruby
   # Already correct - just needs field name update from Phase 1
   plan.plan_id[0..19]  # Will work after model field rename
   ```

2.2. **Fix billing.rb variable naming and field access**
   - Line 70: `catalog = get_catalog(...)` → `plan = get_plan(...)`
   - Line 92: `price: plan.stripe_price_id` → already correct variable
   - Line 103: `catalog_id: plan.catalog_id` → `plan_id: plan.plan_id`
   - Line 201: `CatalogCache.list_catalogs` → `Plan.list_plans`
   - Line 206: `id: plan.catalog_id` → `id: plan.plan_id`
   - Line 253: `::Billing::Models::CatalogCache.load` → `::Billing::Models::Plan.load`
   - Line 257: `id: plan.plan_id` → already correct after field rename

2.3. **Fix plans.rb variable naming**
   - Line 39: `catalog = get_catalog(...)` → `plan = get_plan(...)`
   - Line 41: `unless catalog` → `unless plan`
   - Line 62: `plan.stripe_price_id` → correct variable now
   - Line 79: `catalog_id: plan.catalog_id` → `plan_id: plan.plan_id`

2.4. **Fix catalog_definitions.rb**
   - Line 54: `list_catalog` → `list_plans`
   - Line 67: `.catalog_id` → `.plan_id`
   - Line 85: `load(catalog_id)` → `load(plan_id)`
   - Line 124: `list_catalog` → `list_plans`
   - Line 125: `item.catalog_id` → `item.plan_id`
   - Update method signatures: `catalog_id` → `plan_id`

**Files Changed**: 3 files

---

### Phase 3: Comprehensive Field/Method Updates
**Objective**: Update all remaining references
**Risk**: Medium (comprehensive changes)
**Estimated Time**: 3 hours

#### Tasks:

3.1. **Rename catalog_definitions.rb → plan_definitions.rb**
   - Move file to new location
   - Update all method comments and documentation
   - Update method names:
     - `catalog_name(catalog_id)` → `plan_name(plan_id)`
     - `available_catalogs` → `available_plans`
   - Update all `catalog_id` parameters → `plan_id`

3.2. **Update controllers/capabilities.rb**
   - Line 183: `list_catalogs` → `list_plans`
   - Line 186: `plan.catalog_id` → `plan.plan_id`
   - Update variable names for consistency

3.3. **Update Organization/Customer models**
   - Add new field `plan_id` (with underscore)
   - Keep `planid` for backwards compatibility (deprecated)
   - Add getter/setter to sync between fields:
     ```ruby
     def plan_id=(value)
       @plan_id = value
       @planid = value  # Sync deprecated field
     end

     def plan_id
       @plan_id ||= @planid  # Fallback to old field
     end
     ```

3.4. **Update with_organization_billing.rb**
   - Update all references from `planid` → `plan_id`
   - Update Stripe metadata sync logic
   - Keep backward compatibility checks

**Files Changed**: ~10 files

---

### Phase 4: Test Suite Updates
**Objective**: Update all tests to use new terminology
**Risk**: Low (tests validate correctness)
**Estimated Time**: 2 hours

#### Tasks:

4.1. **Rename test file**
   - Move `try/billing/01_catalog_cache_try.rb` → `01_plan_try.rb`

4.2. **Update test file content**
   - Line 7: Comment "PlanCache tests" (already correct!)
   - Line 13: `require 'apps/web/billing/models/plan'`
   - Line 16: `Billing::Models::Plan.clear_plans_cache`
   - Line 20: `Billing::Models::Plan.new(`
   - Line 21: `plan_id:` → already using correct parameter! (field was wrong)
   - Line 37, 41, 54, 55, 58, 59, 72-78: Update class and method names
   - Line 72: Fix variable bug: `@yearly_catalog.save` → `@yearly_plan.save`

4.3. **Update other test files**
   - `try/billing/02_organization_billing_try.rb`
   - `try/billing/04_capabilities_try.rb`
   - `try/billing/05_cli_commands_try.rb`

4.4. **Run test suite**
   - Verify all billing tests pass
   - Check for any remaining failures

**Files Changed**: ~4 files

---

### Phase 5: Create Catalog Collection Class
**Objective**: Create new Catalog class for collection operations
**Risk**: Low (new functionality)
**Estimated Time**: 1 hour

#### Tasks:

5.1. **Create lib/onetime/billing/catalog.rb**
   ```ruby
   module Billing
     module Models
       # Represents the collection of all available billing plans
       #
       # The Catalog is the container; Plans are the items within it.
       # Use this class for catalog-level operations like listing
       # all plans, filtering by criteria, etc.
       #
       # Individual plan operations belong on the Plan class.
       class Catalog
         class << self
           # List all available (non-legacy) plans
           def available_plans
             Plan.list_plans.reject { |plan| legacy_plan?(plan.plan_id) }
           end

           # Find plans with specific capability
           def plans_with_capability(capability)
             Plan.list_plans.select { |plan|
               plan.parsed_capabilities.include?(capability.to_s)
             }
           end

           # Check if plan is legacy (v0)
           def legacy_plan?(plan_id)
             plan_id.match?(/_v0(_|$)/)
           end

           # Refresh entire catalog from Stripe
           def refresh_from_stripe
             Plan.refresh_from_stripe
           end

           # Clear entire catalog cache
           def clear
             Plan.clear_plans_cache
           end
         end
       end
     end
   end
   ```

5.2. **Update plan_definitions.rb to use Catalog class**
   - Move `legacy_plan?` to Catalog class
   - Move `available_catalogs` → `Catalog.available_plans`
   - Update `upgrade_path_for` to use `Catalog.plans_with_capability`

**Files Changed**: 2 files (1 new, 1 updated)

---

### Phase 6: Documentation & CLI Updates
**Objective**: Update documentation and CLI commands
**Risk**: Very Low
**Estimated Time**: 2 hours

#### Tasks:

6.1. **Update documentation**
   - Rename `docs/billing/catalogue-definitions.md` → `plan-definitions.md`
   - Update all `catalog_id` → `plan_id` in docs
   - Update all references to "catalog" when meaning singular item
   - Document new Catalog class
   - Update API examples

6.2. **Update CLI commands**
   - Check `apps/web/billing/cli/catalog_command.rb`
   - Update to use `Plan.list_plans`
   - Update help text and output labels

6.3. **Create migration guide**
   - Document breaking changes
   - Provide upgrade path for external API consumers
   - Document backward compatibility for `planid` field

**Files Changed**: ~5 files

---

### Phase 7: Stripe Integration Verification
**Objective**: Ensure Stripe sync continues working
**Risk**: Low (mostly verification)
**Estimated Time**: 1 hour

#### Tasks:

7.1. **Verify Stripe metadata mapping**
   - Stripe `plan_id` metadata → Plan `plan_id` field ✅ (aligned!)
   - Update sync logic in `refresh_from_stripe`
   - Line 186: `catalog_id = product.metadata['catalog_id'] || ...`
     → `plan_id = product.metadata['plan_id'] || product.metadata['catalog_id'] || ...`
   - Maintain backward compatibility for existing `catalog_id` in Stripe

7.2. **Update CLI product commands**
   - `apps/web/billing/cli/products_create_command.rb` - already uses `plan_id` ✅
   - `apps/web/billing/cli/products_update_command.rb` - already uses `plan_id` ✅
   - No changes needed (Stripe interface already correct!)

7.3. **Test full sync flow**
   - Create test Stripe product with metadata
   - Run `refresh_from_stripe`
   - Verify Plan cache is populated correctly

**Files Changed**: 1 file

---

## Testing Strategy

### Unit Tests
- [ ] All Tryout tests pass: `bundle exec try try/billing/`
- [ ] Plan model tests: `bundle exec try try/billing/01_plan_try.rb`
- [ ] Organization billing tests: `bundle exec try try/billing/02_organization_billing_try.rb`
- [ ] Capabilities tests: `bundle exec try try/billing/04_capabilities_try.rb`

### Integration Tests
- [ ] CLI commands work: `bin/ots billing --list`
- [ ] API endpoints return correct data:
  - `GET /billing/plans`
  - `GET /billing/org/:extid`
- [ ] Stripe sync works: `Plan.refresh_from_stripe`
- [ ] Checkout flow works end-to-end
- [ ] Customer portal redirect works

### Regression Tests
- [ ] Existing organizations can still load their plan data
- [ ] Backward compatibility with `planid` field works
- [ ] Stripe webhooks continue to process correctly

---

## Redis Migration Strategy

### Key Structure Changes

**Before:**
```
billing_catalog:{catalog_id}  # e.g., billing_catalog:identity_v1_monthly
```

**After:**
```
billing_plan:{plan_id}  # e.g., billing_plan:identity_v1_monthly
```

### Migration Approach: **Parallel Keys**

1. **Phase 1-4**: Keep old keys, write to both old and new keys
2. **Phase 5**: Switch reads to new keys, still write to both
3. **Phase 6**: Stop writing to old keys
4. **Phase 7**: Clean up old keys with migration script

**Reason**: Zero-downtime migration, gradual cutover

### Migration Script (Optional)

```ruby
# bin/migrate_plan_cache_keys.rb
old_pattern = "billing_catalog:*"
Familia.redis.scan_each(match: old_pattern) do |old_key|
  catalog_id = old_key.sub("billing_catalog:", "")
  new_key = "billing_plan:#{catalog_id}"

  # Copy to new key
  Familia.redis.copy(old_key, new_key)

  # Set same TTL
  ttl = Familia.redis.ttl(old_key)
  Familia.redis.expire(new_key, ttl) if ttl > 0

  puts "Migrated: #{old_key} → #{new_key}"
end
```

**Note**: Since we're renaming the prefix in the model, Familia will automatically use the new key structure. Old keys will expire naturally after 12 hours (default expiration).

---

## Rollback Plan

If issues arise after deployment:

### Immediate Rollback (< 1 hour)
1. Revert Git commits
2. Redeploy previous version
3. No data loss (Redis keys still have 12h TTL)

### Partial Rollback (Field-Level)
1. Revert Organization `plan_id` → `planid` change
2. Keep using Plan model internally
3. Map fields at boundary

### Data Consistency
- No Stripe data changes (external system unchanged)
- Redis keys expire automatically (12h TTL)
- Organization `planid` field maintained for backward compat

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| Breaking API endpoints | Medium | High | Comprehensive testing before deployment |
| Stripe sync failure | Low | High | Maintain backward compat for metadata fields |
| Redis key mismatch | Low | Medium | Familia handles prefix automatically |
| Missing test coverage | Medium | Medium | Review all test files in Phase 4 |
| External API consumers break | Low | High | Maintain `planid` field, document deprecation |

---

## Success Criteria

- [ ] All 6 critical bugs fixed
- [ ] All tests passing (Tryouts, integration)
- [ ] CLI commands functional
- [ ] API endpoints return valid data
- [ ] Stripe sync works correctly
- [ ] Checkout flow works end-to-end
- [ ] No production errors after deployment
- [ ] Documentation updated and accurate

---

## Deployment Checklist

### Pre-Deployment
- [ ] All tests pass locally
- [ ] Code review completed
- [ ] Documentation updated
- [ ] CHANGELOG updated with breaking changes
- [ ] Staging environment tested

### Deployment
- [ ] Deploy to staging
- [ ] Run smoke tests on staging
- [ ] Deploy to production
- [ ] Monitor error logs for 1 hour
- [ ] Run `Plan.refresh_from_stripe` in production console
- [ ] Verify API endpoints return correct data

### Post-Deployment
- [ ] Verify no increased error rates
- [ ] Check Stripe webhook processing
- [ ] Verify customer can complete checkout
- [ ] Monitor for 24 hours

---

## Estimated Total Effort

| Phase | Hours | Risk |
|-------|-------|------|
| 1. Model Core Migration | 2 | Low |
| 2. Fix Critical Bugs | 1 | Low |
| 3. Comprehensive Updates | 3 | Medium |
| 4. Test Suite Updates | 2 | Low |
| 5. Create Catalog Class | 1 | Low |
| 6. Documentation & CLI | 2 | Very Low |
| 7. Stripe Verification | 1 | Low |
| **Total** | **12 hours** | **Low-Medium** |

**Recommended Schedule**: 2 days (1.5 days implementation, 0.5 day testing/deployment)

---

## Next Steps

1. ✅ Review and approve this implementation plan
2. ⏭️ Begin Phase 1: Model Core Migration
3. ⏭️ Execute phases sequentially with testing after each phase
4. ⏭️ Create PR targeting `develop` branch
5. ⏭️ Deploy to staging for validation
6. ⏭️ Deploy to production with monitoring

---

## Notes

- **Backward Compatibility**: Maintained via `planid` field (deprecated but functional)
- **External APIs**: Will continue to work during transition period
- **Stripe Integration**: No changes needed (already uses `plan_id` in metadata)
- **Zero Downtime**: Gradual migration approach ensures no service interruption
- **Data Migration**: Not required (Redis keys expire and regenerate automatically)


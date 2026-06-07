# try/unit/models/organization_entitlements_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Organization entitlements feature - FOCUSED TEST
# Tests the entitlement fallback hierarchy:
# - When billing_enabled: false → return STANDALONE_ENTITLEMENTS (full access)
# - When billing_enabled: true but planid empty → return FREE_TIER_ENTITLEMENTS
# - When billing_enabled: true and plan in cache → return plan entitlements
# - When billing_enabled: true but plan cache miss → raise PlanCacheMissError (fail-closed)

require_relative '../../support/test_models'

OT.boot! :test

# Load Billing module for PlanCacheMissError and Plan model
require_relative '../../../apps/web/billing/errors'
require_relative '../../../apps/web/billing/models/plan'

# Setup test data
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "ent_owner#{@timestamp}@onetimesecret.com")
@org = Onetime::Organization.create!(
  "Entitlements Test Org",
  @owner,
  "billing#{@timestamp}@enttest.com"
)

## Can create organization
@org.class
#=> Onetime::Organization

## Organization includes WithEntitlements feature methods
[@org.respond_to?(:entitlements), @org.respond_to?(:can?), @org.respond_to?(:limit_for)]
#=> [true, true, true]

## STANDALONE MODE TEST: billing disabled returns full entitlements
# Override the private billing_enabled? method for this instance
@org.define_singleton_method(:billing_enabled?) { false }
@org.entitlements.sort
#=> Onetime::Models::Features::WithPlanEntitlements::STANDALONE_ENTITLEMENTS.sort

## Standalone: can? returns true for standard entitlements
@org.can?('api_access')
#=> true

## Standalone: can? returns true for premium entitlements
@org.can?('custom_domains')
#=> true

## Standalone: limit_for returns infinity
@org.limit_for('teams')
#=> Float::INFINITY

## SAAS MODE TEST: billing enabled with empty planid returns FREE tier entitlements
# Clear materialization state to exercise SaaS fallback chain
@org.materialized_entitlements_at = nil
@org.materialized_entitlements.clear
@org.limits_plan.clear
# Switch to billing enabled mode
@org.define_singleton_method(:billing_enabled?) { true }
@org.planid = ""
@org.entitlements.sort
#=> Onetime::Models::Features::WithPlanEntitlements::FREE_TIER_ENTITLEMENTS.sort

## SaaS empty planid: can? returns true for FREE tier entitlements
@org.can?('api_access')
#=> true

## SaaS empty planid: can? returns false for premium entitlements
@org.can?('custom_branding')
#=> false

## SaaS empty planid: limit_for returns FREE tier limit (0 for teams)
@org.limit_for('teams')
#=> 0

## SaaS empty planid: can? returns true for custom_domains (FREE tier key)
@org.can?('custom_domains')
#=> true

## SaaS empty planid: can? returns true for incoming_secrets (FREE tier key)
@org.can?('incoming_secrets')
#=> true

## SaaS empty planid: can? returns true for homepage_secrets (FREE tier key)
@org.can?('homepage_secrets')
#=> true

## SaaS empty planid: can? returns false for custom_branding (bounded set check)
@org.can?('custom_branding')
#=> false

## SaaS empty planid: limit_for('organizations') returns FREE tier max
@org.limit_for('organizations')
#=> 5

## SaaS empty planid: limit_for('total_members_per_org') returns FREE tier max
@org.limit_for('total_members_per_org')
#=> 0

## SaaS empty planid: limit_for('secret_lifetime') returns DEFAULT_FREE_TTL absent env override
## (14 days, matching free_v1 plan in billing.yaml; see #3111)
@org.limit_for('secret_lifetime')
#=> 1_209_600

## SAAS PLAN CACHE MISS TEST: billing enabled but plan not in cache raises PlanCacheMissError (fail-closed)
@org.planid = "nonexistent_plan_#{@timestamp}"
begin
  @org.entitlements
rescue Billing::PlanCacheMissError
  :raised_plan_cache_miss_error
end
#=> :raised_plan_cache_miss_error

## SaaS plan cache miss: can? raises PlanCacheMissError (fail-closed)
begin
  @org.can?('api_access')
rescue Billing::PlanCacheMissError
  :raised_plan_cache_miss_error
end
#=> :raised_plan_cache_miss_error

## SaaS plan cache miss: limit_for raises PlanCacheMissError (fail-closed)
begin
  @org.limit_for('teams')
rescue Billing::PlanCacheMissError
  :raised_plan_cache_miss_error
end
#=> :raised_plan_cache_miss_error

## SaaS plan cache miss: entitlement checks consistently raise PlanCacheMissError
begin
  @org.can?('custom_branding')
rescue Billing::PlanCacheMissError
  :raised_plan_cache_miss_error
end
#=> :raised_plan_cache_miss_error

## SAAS MODE TEST: billing enabled with valid plan via config fallback
# Load a real plan from billing.yaml config (works without Stripe sync)
# Note: This exercises the load_from_config fallback, not Redis cache hit
@test_plan_id = 'identity_plus_v1'
@test_plan_config = Billing::Plan.load_from_config(@test_plan_id)
@test_plan_config.nil?
#=> false

## SaaS with plan via config: setup org with planid pointing to valid plan
# Clear any materialization to force the Plan.load fallback path
@org.materialized_entitlements_at = nil
@org.materialized_entitlements.clear
@org.limits_plan.clear
@org.define_singleton_method(:billing_enabled?) { true }
@org.planid = @test_plan_id
# Entitlements should come from config fallback (billing.yaml)
@org.entitlements.sort
#=> Billing::Plan.load_from_config('identity_plus_v1')[:entitlements].sort

## SaaS with plan via config: can? returns true for plan entitlements
@org.can?('api_access')
#=> true

## SaaS with plan via config: can? returns true for custom_branding (identity_plus_v1 feature)
@org.can?('custom_branding')
#=> true

## SaaS with plan via config: can? returns false for entitlements not in plan
# manage_teams is in team_plus_v1, not identity_plus_v1
@org.can?('manage_teams')
#=> false

## SaaS with plan via config: limit_for returns plan-specific limit from config
# identity_plus_v1 has organizations.max = 1 (from billing.yaml)
# Verify limit_for returns the same value as in the config
@org.limit_for('organizations')
#=> Billing::Plan.load_from_config('identity_plus_v1')[:limits]['organizations.max'].to_i

## SAAS MATERIALIZED PATH TEST: materialized org reads from local storage
# Materialize the org with plan entitlements using config data
@org.materialize_entitlements_from_config(@test_plan_config)
@org.entitlements_materialized?
#=> true

## Materialized path: entitlements come from materialized_entitlements set
@org.materialized_entitlements.to_a.sort
#=> Billing::Plan.load_from_config('identity_plus_v1')[:entitlements].sort

## Materialized path: can? reads from materialized entitlements
@org.can?('custom_branding')
#=> true

## Materialized path: can? returns false for non-materialized entitlements
@org.can?('manage_teams')
#=> false

## Materialized path: limit_for reads from materialized limits_plan
# identity_plus_v1 has secret_lifetime.max = 2592000 (30 days per billing.yaml)
# Verify limit_for returns the same value as in the materialized config
@org.limit_for('secret_lifetime')
#=> Billing::Plan.load_from_config('identity_plus_v1')[:limits]['secret_lifetime.max'].to_i

## Materialized path: grants override plan entitlements
@org.grant_entitlement('manage_teams')
@org.can?('manage_teams')
#=> true

## Materialized path: revokes override plan entitlements
@org.revoke_entitlement('custom_branding')
@org.can?('custom_branding')
#=> false

## Materialized path: clear overrides restores plan entitlements
@org.clear_entitlement_overrides
[@org.can?('custom_branding'), @org.can?('manage_teams')]
#=> [true, false]

# Teardown
@org.destroy!
@owner.destroy!

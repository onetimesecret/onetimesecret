# try/unit/models/organization_entitlements_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Organization entitlements feature - FOCUSED TEST
# Tests the entitlement fallback hierarchy:
# - When billing_enabled: false → return STANDALONE_ENTITLEMENTS (full access)
# - When billing_enabled: true but planid empty → return FREE_TIER_ENTITLEMENTS
# - When billing_enabled: true and plan in cache → return plan entitlements
# - When billing_enabled: true but plan cache miss → return FREE_TIER_ENTITLEMENTS (graceful degradation)

require_relative '../../support/test_models'

OT.boot! :test

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
#=> Onetime::Models::Features::WithEntitlements::STANDALONE_ENTITLEMENTS.sort

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
# Switch to billing enabled mode
@org.define_singleton_method(:billing_enabled?) { true }
@org.planid = ""
@org.entitlements.sort
#=> Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS.sort

## SaaS empty planid: can? returns true for FREE tier entitlements
@org.can?('api_access')
#=> true

## SaaS empty planid: can? returns false for premium entitlements
@org.can?('custom_domains')
#=> false

## SaaS empty planid: limit_for returns FREE tier limit (0 for teams)
@org.limit_for('teams')
#=> 0

## SAAS PLAN CACHE MISS TEST: billing enabled but plan not in cache returns FREE tier (graceful degradation)
@org.planid = "nonexistent_plan_#{@timestamp}"
@org.entitlements.sort
#=> Onetime::Models::Features::WithEntitlements::FREE_TIER_ENTITLEMENTS.sort

## SaaS plan cache miss: can? returns true for FREE tier entitlements (api_access is in FREE tier)
@org.can?('api_access')
#=> true

## SaaS plan cache miss: limit_for returns FREE tier limit (0 for teams)
@org.limit_for('teams')
#=> 0

## SaaS plan cache miss: can? returns false for premium entitlements not in FREE tier
[@org.can?('custom_domains'), @org.can?('api_access'), @org.can?('audit_logs')]
#=> [false, true, false]

# Teardown
@org.destroy!
@owner.destroy!

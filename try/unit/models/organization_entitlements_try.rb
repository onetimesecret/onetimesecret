# try/unit/models/organization_entitlements_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Organization entitlements feature - FOCUSED TEST
# Tests the critical SaaS free tier fix:
# - When billing_enabled: true but plan cache is empty → return [] (fail-closed)
# - When billing_enabled: false → return full entitlements (standalone mode)

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

## SAAS MODE TEST: billing enabled with empty planid returns empty array
# Switch to billing enabled mode
@org.define_singleton_method(:billing_enabled?) { true }
@org.planid = ""
@org.entitlements
#=> []

## SaaS empty planid: can? returns false
@org.can?('api_access')
#=> false

## SaaS empty planid: limit_for returns 0
@org.limit_for('teams')
#=> 0

## SAAS PLAN CACHE MISS TEST: billing enabled but plan not in cache returns empty array (CRITICAL FIX)
@org.planid = "nonexistent_plan_#{@timestamp}"
@org.entitlements
#=> []

## SaaS plan cache miss: can? returns false (fail-closed behavior)
@org.can?('api_access')
#=> false

## SaaS plan cache miss: limit_for returns 0 (fail-closed behavior)
@org.limit_for('teams')
#=> 0

## SaaS plan cache miss: can? returns false for all entitlements
[@org.can?('custom_domains'), @org.can?('api_access'), @org.can?('audit_logs')]
#=> [false, false, false]

# Teardown
@org.destroy!
@owner.destroy!

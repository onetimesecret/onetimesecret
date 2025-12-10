# try/unit/models/organization_capabilities_try.rb
#
# frozen_string_literal: true

#
# Unit tests for Organization capabilities feature - FOCUSED TEST
# Tests the critical SaaS free tier fix:
# - When billing_enabled: true but plan cache is empty → return [] (fail-closed)
# - When billing_enabled: false → return full capabilities (standalone mode)

require_relative '../../support/test_models'

OT.boot! :test

# Setup test data
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "cap_owner#{@timestamp}@onetimesecret.com")
@org = Onetime::Organization.create!(
  "Capabilities Test Org",
  @owner,
  "billing#{@timestamp}@captest.com"
)

## Can create organization
@org.class
#=> Onetime::Organization

## Organization includes WithCapabilities feature methods
[@org.respond_to?(:capabilities), @org.respond_to?(:can?), @org.respond_to?(:limit_for)]
#=> [true, true, true]

## STANDALONE MODE TEST: billing disabled returns full capabilities
# Override the private billing_enabled? method for this instance
@org.define_singleton_method(:billing_enabled?) { false }
@org.capabilities.sort
#=> Onetime::Models::Features::WithCapabilities::STANDALONE_CAPABILITIES.sort

## Standalone: can? returns true for standard capabilities
@org.can?('create_secrets')
#=> true

## Standalone: can? returns true for premium capabilities
@org.can?('custom_domains')
#=> true

## Standalone: limit_for returns infinity
@org.limit_for('teams')
#=> Float::INFINITY

## SAAS MODE TEST: billing enabled with empty planid returns empty array
# Switch to billing enabled mode
@org.define_singleton_method(:billing_enabled?) { true }
@org.planid = ""
@org.capabilities
#=> []

## SaaS empty planid: can? returns false
@org.can?('create_secrets')
#=> false

## SaaS empty planid: limit_for returns 0
@org.limit_for('teams')
#=> 0

## SAAS PLAN CACHE MISS TEST: billing enabled but plan not in cache returns empty array (CRITICAL FIX)
@org.planid = "nonexistent_plan_#{@timestamp}"
@org.capabilities
#=> []

## SaaS plan cache miss: can? returns false (fail-closed behavior)
@org.can?('create_secrets')
#=> false

## SaaS plan cache miss: limit_for returns 0 (fail-closed behavior)
@org.limit_for('teams')
#=> 0

## SaaS plan cache miss: can? returns false for all capabilities
[@org.can?('custom_domains'), @org.can?('api_access'), @org.can?('audit_logs')]
#=> [false, false, false]

# Teardown
@org.destroy!
@owner.destroy!

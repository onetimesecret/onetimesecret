# try/unit/billing/build_limits_hash_try.rb
#
# frozen_string_literal: true

# Unit tests for Billing::Controllers::Entitlements#build_limits_hash
#
# The method has two paths:
# - Materialized org: reads from org.limits_plan (no Plan.load)
# - Unmaterialized org: falls back to Plan.load (legacy path)
#
# Run: try --agent try/unit/billing/build_limits_hash_try.rb

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/controllers/entitlements'

OT.boot! :test

# Minimal req/res stubs so the controller can be instantiated
class StubReq
  attr_reader :env, :params
  def initialize
    @env    = {}
    @params = {}
  end
  def locale; 'en'; end
  def user; nil; end
end

class StubRes
  attr_accessor :status
  def initialize; @status = 200; end
end

def make_controller
  req = StubReq.new
  res = StubRes.new
  # Avoid ensure_customer_has_workspace side-effects when cust is nil
  ctrl = Billing::Controllers::Entitlements.allocate
  ctrl.instance_variable_set(:@req, req)
  ctrl.instance_variable_set(:@res, res)
  ctrl.instance_variable_set(:@locale, 'en')
  ctrl.instance_variable_set(:@region, 'LL')
  ctrl
end

# Setup test data
@timestamp = Familia.now.to_i
@owner = Onetime::Customer.create!(email: "limits_hash_owner#{@timestamp}@example.com")
@org   = Onetime::Organization.create!("Limits Hash Test Org", @owner, @owner.email)

@ctrl  = make_controller

## Returns empty hash when planid is blank
@org.planid = ''
@org.save
@ctrl.send(:build_limits_hash, @org)
#=> {}

## Materialized org: returns limits from limits_plan without calling Plan.load
# Materialize a set of limits directly into the org (no plan in cache required)
@org.planid = 'test_plan_materialized'
@org.save
@org.limits_plan['teams.max']           = '5'
@org.limits_plan['secret_lifetime.max'] = '2592000'
@org.materialized_entitlements_at       = "#{@timestamp}:abc123def456"
@org.save

result = @ctrl.send(:build_limits_hash, @org)
[result['teams.max'], result['secret_lifetime.max']]
#=> [5, 2592000]

## Materialized org: 'unlimited' string values become nil
@org.limits_plan['members_per_team.max'] = 'unlimited'
result = @ctrl.send(:build_limits_hash, @org)
result['members_per_team.max']
#=> nil

## Materialized org: numeric string values become integers
@org.limits_plan['organizations.max'] = '10'
result = @ctrl.send(:build_limits_hash, @org)
result['organizations.max']
#=> 10

## Materialized org: does not call Plan.load (plan cache is empty, still returns data)
# BillingTestHelpers disables billing by default so Plan.load returns nil.
# If the materialized branch called Plan.load it would get nil and return {}.
# Non-empty output proves the materialized branch ran.
BillingTestHelpers.clear_plan_cache!
result = @ctrl.send(:build_limits_hash, @org)
result.empty?
#=> false

## Unmaterialized org: falls back to Plan.load and returns {} when plan not found
@org2 = Onetime::Organization.create!("Unmaterialized Org #{@timestamp}", @owner, "unmaterialized#{@timestamp}@example.com")
@org2.planid = "nonexistent_plan_#{@timestamp}"
@org2.save
# Load billing so ::Billing::Plan is defined for the fallback path
BillingTestHelpers.ensure_billing_loaded!
BillingTestHelpers.clear_plan_cache!
# materialized_entitlements_at is empty => entitlements_materialized? returns false
# Plan.load returns nil (plan not in cache) => method returns {}
@ctrl.send(:build_limits_hash, @org2)
#=> {}

## Unmaterialized org with plan in cache: returns plan limits
BillingTestHelpers.with_billing_enabled(plans: [{
  plan_id: 'fallback_test_plan',
  name: 'Fallback Plan',
  tier: 'identity',
  interval: 'month',
  region: 'us',
  entitlements: ['api_access'],
  limits: { 'teams.max' => '3', 'members_per_team.max' => 'unlimited' }
}]) do
  @org2.planid = 'fallback_test_plan'
  @org2.save
  result = @ctrl.send(:build_limits_hash, @org2)
  [result['teams.max'], result['members_per_team.max']]
end
#=> [3, nil]

# Teardown
@org.destroy!  rescue nil
@org2.destroy! rescue nil
@owner.destroy! rescue nil

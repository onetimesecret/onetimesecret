#!/usr/bin/env ruby

# frozen_string_literal: true

# Billing Isolation Verification Tests
#
# Tests Issue #2228 fix: Verify that billing is disabled by default
# in tests and that plan cache isolation works correctly.
#
# These tests verify:
# 1. Billing is disabled by default (no config file loaded)
# 2. Entitlements fall back to standalone mode when billing disabled
# 3. Plan cache doesn't persist between test runs
# 4. BillingTestHelpers properly isolate test state

require_relative '../support/test_helpers'
require_relative '../../apps/web/billing/lib/test_support/billing_helpers'

## Billing config file exists in test environment (billing.test.yaml)
# ConfigResolver finds apps/web/billing/spec/billing.test.yaml
Onetime::BillingConfig.instance.path.nil?
#=> false

## Billing config file actually exists on disk
File.exist?(Onetime::BillingConfig.instance.path)
#=> true

## Billing config returns disabled state
Onetime::BillingConfig.instance.enabled?
#=> false

## Billing::Plan cache is empty by default
# This tests that no plans persist from previous test runs
Billing::Plan.all.empty?
#=> true

## Creating a test class with entitlements mixin
# Tests that billing_enabled? works correctly in the mixin
@test_class = Class.new do
  include Onetime::Models::Features::WithEntitlements

  attr_accessor :planid

  def initialize(planid)
    @planid = planid
  end

  # Make billing_enabled? public for testing
  public :billing_enabled?
end

@obj = @test_class.new('free')
@obj.billing_enabled?
#=> false

## Object gets standalone entitlements when billing disabled
# Standalone mode gives all base entitlements without restrictions
@obj.can?(:api_access)
#=> true

## Object entitlements array is not empty in standalone mode
# Even with billing disabled, base entitlements should be available
!@obj.entitlements.empty?
#=> true

## BillingTestHelpers can enable billing temporarily
result = nil
BillingTestHelpers.with_billing_enabled do
  result = Onetime::BillingConfig.instance.enabled?
end
result
#=> true

## Billing is disabled again after with_billing_enabled block
Onetime::BillingConfig.instance.enabled?
#=> false

## BillingTestHelpers can populate test plans
plans_data = [{
  plan_id: 'test_plan',
  name: 'Test Plan',
  tier: 1,
  interval: 'month',
  region: 'us',
  entitlements: ['test_entitlement'],
  limits: { 'test.limit' => '5' }
}]

BillingTestHelpers.with_billing_enabled(plans: plans_data) do
  plan = Billing::Plan.find('test_plan')
  plan.nil? ? 'not_found' : plan.plan_id
end
#=> 'test_plan'

## Plan cache is cleared after with_billing_enabled block
# This ensures test isolation - no plans persist
Billing::Plan.all.empty?
#=> true

## Familia is configured with test Redis URI
# Must use port 2121 for tests to avoid conflicts
Familia.uri.to_s.include?('2121')
#=> true

## clear_plan_cache! safely handles empty cache
# Should not raise errors when cache is already empty
begin
  BillingTestHelpers.clear_plan_cache!
  'success'
rescue => e
  "error: #{e.message}"
end
#=> 'success'

## cleanup_billing_state! resets all billing state
# Should clear cache and disable billing
BillingTestHelpers.cleanup_billing_state!
[Onetime::BillingConfig.instance.enabled?, Billing::Plan.all.empty?]
#=> [false, true]

## restore_billing!(enabled: true) enables billing
# When enabled: true is passed, billing should be force-enabled
@before_enabled = Onetime::BillingConfig.instance.enabled?
BillingTestHelpers.restore_billing!(enabled: true)
@after_enabled = Onetime::BillingConfig.instance.enabled?
# Disable billing again for subsequent tests
BillingTestHelpers.disable_billing!
@final_enabled = Onetime::BillingConfig.instance.enabled?
# Test that before was disabled, after was enabled, final is disabled
[@before_enabled, @after_enabled, @final_enabled]
#=> [false, true, false]

## ensure_familia_configured! is idempotent
# Should not change URI if already configured for test
original_uri = Familia.uri.to_s
BillingTestHelpers.ensure_familia_configured!
Familia.uri.to_s == original_uri
#=> true

## Test isolation: Multiple sequential with_billing_enabled blocks
# Each block should start with clean state
results = []
3.times do |i|
  BillingTestHelpers.with_billing_enabled(plans: [{
    plan_id: "plan_#{i}",
    name: "Plan #{i}",
    tier: 1,
    interval: 'month',
    region: 'us',
    entitlements: [],
    limits: {}
  }]) do
    # Each iteration should only see its own plan
    results << Billing::Plan.all.size
  end
end
results
#=> [1, 1, 1]

## Final verification: Billing is still disabled
# After all tests, billing should be disabled
Onetime::BillingConfig.instance.enabled?
#=> false

## Final verification: Plan cache is empty
# No test plans should persist
Billing::Plan.all.empty?
#=> true

# ---------------------------------------------------------------------------
# Regional isolation tests (Issue #2228 follow-up)
#
# correct_region? guards both the refresh_from_stripe (collect_stripe_plans)
# and the webhook handler paths. Each testcase builds its own stub objects
# inline so there is no cross-testcase state dependency.
# ---------------------------------------------------------------------------

## correct_region? returns true when no region is configured (pass-through)
# With no region configured the filter is disabled (backward-compatible).
Onetime::BillingConfig.instance.config['region'] = nil
_nz = Struct.new(:id, :name, :metadata).new('prod_nz', 'Identity Plus (NZ)',
  { 'app' => 'onetimesecret', 'region' => 'NZ', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_nz)
#=> true

## correct_region? accepts NZ product when region configured as 'NZ'
Onetime::BillingConfig.instance.config['region'] = 'NZ'
_nz = Struct.new(:id, :name, :metadata).new('prod_nz', 'Identity Plus (NZ)',
  { 'app' => 'onetimesecret', 'region' => 'NZ', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_nz)
#=> true

## correct_region? rejects CA product when region configured as 'NZ'
Onetime::BillingConfig.instance.config['region'] = 'NZ'
_ca = Struct.new(:id, :name, :metadata).new('prod_ca', 'Identity Plus (CA)',
  { 'app' => 'onetimesecret', 'region' => 'CA', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_ca)
#=> false

## correct_region? accepts CA product when region configured as 'CA'
Onetime::BillingConfig.instance.config['region'] = 'CA'
_ca = Struct.new(:id, :name, :metadata).new('prod_ca', 'Identity Plus (CA)',
  { 'app' => 'onetimesecret', 'region' => 'CA', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_ca)
#=> true

## correct_region? rejects NZ product when region configured as 'CA'
Onetime::BillingConfig.instance.config['region'] = 'CA'
_nz = Struct.new(:id, :name, :metadata).new('prod_nz', 'Identity Plus (NZ)',
  { 'app' => 'onetimesecret', 'region' => 'NZ', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_nz)
#=> false

## correct_region? treats blank string config as no region (pass-through)
Onetime::BillingConfig.instance.config['region'] = '   '
_nz = Struct.new(:id, :name, :metadata).new('prod_nz', 'Identity Plus (NZ)',
  { 'app' => 'onetimesecret', 'region' => 'NZ', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
Billing::Plan.correct_region?(_nz)
#=> true

## Regional filter: only NZ product accepted when region is 'NZ'
# Two products share the same plan_id metadata — the bug scenario.
# With NZ configured only the NZ product passes the guard.
Onetime::BillingConfig.instance.config['region'] = 'NZ'
_nz_p = Struct.new(:id, :name, :metadata).new('prod_nz', 'Identity Plus (NZ)',
  { 'app' => 'onetimesecret', 'region' => 'NZ', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
_ca_p = Struct.new(:id, :name, :metadata).new('prod_ca', 'Identity Plus (CA)',
  { 'app' => 'onetimesecret', 'region' => 'CA', 'plan_id' => 'identity_plus_v1',
    'tier' => 'single_account', 'tenancy' => 'multi' })
[_nz_p, _ca_p].select { |p| Billing::Plan.correct_region?(p) }.map { |p| p.metadata['region'] }
#=> ['NZ']

## Cleanup: reset region config to nil after regional isolation tests
Onetime::BillingConfig.instance.config['region'] = nil
Onetime::BillingConfig.instance.region.nil?
#=> true

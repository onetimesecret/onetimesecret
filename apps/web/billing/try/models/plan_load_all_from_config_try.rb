# apps/web/billing/try/models/plan_load_all_from_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'
require_relative '../../lib/test_support/billing_helpers'

# Billing::Plan.load_all_from_config tests
#
# Tests loading all plans from billing.yaml config into Redis cache.
# Uses spec/billing.test.yaml via ConfigResolver when RACK_ENV=test.
#
# Design note: Plans are family-keyed (e.g., "identity_plus_v1") with
# interval variants stored in a nested `prices` hashkey.

## Setup: Load billing models
require 'apps/web/billing/models/plan'

## Setup: Enable billing and ensure Familia is configured
BillingTestHelpers.restore_billing!(enabled: true)

## Setup: Clear any existing plan cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Load all plans from config
@count = Billing::Plan.load_all_from_config
@count.class
#=> Integer

## Should load 1 plan family (identity_plus_v1 with month+year prices)
# Free tier has no prices so it's skipped
@count
#=> 1

## Verify plan was saved to Redis
Billing::Plan.instances.size
#=> 1

## List all loaded plans
@plans = Billing::Plan.list_plans
@plans.size
#=> 1

## Verify plan exists (family-keyed, no interval suffix)
@plan = Billing::Plan.load('identity_plus_v1')
@plan.nil?
#=> false

## Verify plan_id (family-keyed)
@plan.plan_id
#=> 'identity_plus_v1'

## Verify tier
@plan.tier
#=> 'single_team'

## Verify region
@plan.region
#=> 'EU'

## Verify name
@plan.name
#=> 'Identity Plus'

## Verify currency (family-level)
@plan.currency
#=> 'cad'

## Verify plan has both intervals available
@plan.available_intervals.sort
#=> [:month, :year]

## Verify monthly price data
@monthly_price = @plan.price_for(:month)
@monthly_price[:amount]
#=> '1200'

## Verify monthly stripe_price_id
@monthly_price[:stripe_price_id]
#=> 'price_test_monthly'

## Verify yearly price data
@yearly_price = @plan.price_for(:year)
@yearly_price[:amount]
#=> '12000'

## Verify yearly stripe_price_id
@yearly_price[:stripe_price_id]
#=> 'price_test_yearly'

## Verify entitlements match config (derive expected count from source of truth)
@config_plans = Billing::Config.load_plans
@expected_entitlements = @config_plans.dig('identity_plus_v1', 'entitlements') || []
@plan.entitlements.size == @expected_entitlements.size
#=> true

## Verify all config entitlements were loaded
@expected_entitlements.all? { |e| @plan.entitlements.member?(e) }
#=> true

## Verify entitlements include core values
@plan.entitlements.member?('create_secrets')
#=> true

## Verify limits were loaded (all config limits present as .max keys)
@config_limits = @config_plans.dig('identity_plus_v1', 'limits') || {}
@expected_limit_keys = @config_limits.keys.map { |k| "#{k}.max" }.sort
@plan.limits_hash.keys.sort == @expected_limit_keys
#=> true

## Verify unlimited custom_domains limit
@plan.limits_hash['custom_domains.max']
#=> Float::INFINITY

## Verify members_per_team limit
@plan.limits_hash['members_per_team.max']
#=> 10

## Verify get_plan works with tier/interval/region
@plan_via_get = Billing::Plan.get_plan('single_team', 'monthly', 'EU')
@plan_via_get.plan_id
#=> 'identity_plus_v1'

## Verify get_plan works with yearly interval
@plan_via_yearly = Billing::Plan.get_plan('single_team', 'yearly', 'EU')
@plan_via_yearly.plan_id
#=> 'identity_plus_v1'

## Same plan returned for both intervals (family-keyed)
@plan_via_get.plan_id == @plan_via_yearly.plan_id
#=> true

## Test clearing and reloading (clear_first: false)
@before_count = Billing::Plan.instances.size
@reload_count = Billing::Plan.load_all_from_config(clear_first: false)
@after_count  = Billing::Plan.instances.size
[@before_count, @reload_count, @after_count]
#=> [1, 1, 1]

## Test clearing and reloading (clear_first: true, default)
@reload_count = Billing::Plan.load_all_from_config
@reload_count
#=> 1

## Verify instances were updated after reload
Billing::Plan.instances.size
#=> 1

## Teardown: Clear cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Teardown: Restore billing state
BillingTestHelpers.cleanup_billing_state!
true
#=> true

# apps/web/billing/try/models/plan_load_all_from_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'
require_relative '../../lib/test_support/billing_helpers'

# Billing::Operations::Catalog::ConfigLoader.load_all_from_config tests
#
# Tests loading all plans from billing.yaml config into Redis cache.
# Uses spec/billing.test.yaml via ConfigResolver when RACK_ENV=test.
#
# Plans are keyed by canonical family ID (e.g., identity_plus_v1) with
# monthly and yearly prices as nested data.

## Setup: Load billing models
require 'apps/web/billing/models/plan'
require 'apps/web/billing/operations/catalog/config_loader'

## Setup: Enable billing and ensure Familia is configured
BillingTestHelpers.restore_billing!(enabled: true)

## Setup: Clear any existing plan cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Load all plans from config
@count = Billing::Operations::Catalog::ConfigLoader.load_all_from_config
@count.class
#=> Integer

## Should load plans keyed by family ID (not suffixed)
@count
#=> 1

## Verify plan was saved to Redis
Billing::Plan.instances.size
#=> 1

## List all loaded plans
@plans = Billing::Plan.list_plans
@plans.size
#=> 1

## Verify plan exists by canonical family ID
@plan = Billing::Plan.load('identity_plus_v1')
@plan.nil?
#=> false

## Verify plan attributes
@plan.plan_id
#=> 'identity_plus_v1'

## Verify tier
@plan.tier
#=> 'single_account'

## Verify region
@plan.region
#=> 'EU'

## Verify name
@plan.name
#=> 'Identity Plus'

## Verify currency
@plan.currency
#=> 'cad'

## Verify plan has both intervals available
@plan.available_intervals.sort
#=> ['month', 'year']

## Verify monthly price data
@monthly_price = @plan.price_for('month')
@monthly_price['amount']
#=> '1200'

## Verify monthly stripe_price_id
@monthly_price['stripe_price_id']
#=> 'price_test_monthly'

## Verify yearly price data
@yearly_price = @plan.price_for('year')
@yearly_price['amount']
#=> '12000'

## Verify yearly stripe_price_id
@yearly_price['stripe_price_id']
#=> 'price_test_yearly'

## Verify entitlements match config
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

## Verify limits were loaded
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
@plan_via_get = Billing::Plan.get_plan('single_account', 'month', 'EU')
@plan_via_get&.plan_id
#=> 'identity_plus_v1'

## Verify get_plan works with yearly interval
@plan_via_yearly = Billing::Plan.get_plan('single_account', 'year', 'EU')
@plan_via_yearly&.plan_id
#=> 'identity_plus_v1'

## Same plan returned for both intervals (family-keyed)
@plan_via_get.plan_id == @plan_via_yearly.plan_id
#=> true

## Test clearing and reloading (clear_first: false)
@before_count = Billing::Plan.instances.size
@reload_count = Billing::Operations::Catalog::ConfigLoader.load_all_from_config(clear_first: false)
@after_count  = Billing::Plan.instances.size
[@before_count, @reload_count, @after_count]
#=> [1, 1, 1]

## Test clearing and reloading (clear_first: true, default)
@reload_count = Billing::Operations::Catalog::ConfigLoader.load_all_from_config
@reload_count
#=> 1

## Verify instances were updated after reload
Billing::Plan.instances.size
#=> 1

## Cleanup
Billing::Plan.clear_cache

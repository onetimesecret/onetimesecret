# apps/web/billing/try/models/plan_load_all_from_config_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'
require_relative '../../lib/test_support/billing_helpers'

# Billing::Plan.load_all_from_config tests
#
# Tests loading all plans from billing.yaml config into Redis cache.
# Uses spec/billing.test.yaml via ConfigResolver when RACK_ENV=test.

## Setup: Load billing models
require 'apps/web/billing/models/plan'

## Setup: Enable billing and ensure Familia is configured
BillingTestHelpers.restore_billing!

## Setup: Clear any existing plan cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Load all plans from config
@count = Billing::Plan.load_all_from_config
@count.class
#=> Integer

## Should load 2 plans (identity_plus_v1_monthly + identity_plus_v1_yearly)
# Free tier has no prices so it's skipped
@count
#=> 2

## Verify plans were saved to Redis
Billing::Plan.instances.size
#=> 2

## List all loaded plans
@plans = Billing::Plan.list_plans
@plans.size
#=> 2

## Verify monthly plan exists
@monthly = Billing::Plan.load('identity_plus_v1_monthly')
@monthly.nil?
#=> false

## Verify monthly plan attributes
@monthly.plan_id
#=> 'identity_plus_v1_monthly'

## Verify tier
@monthly.tier
#=> 'single_team'

## Verify interval
@monthly.interval
#=> 'month'

## Verify region
@monthly.region
#=> 'EU'

## Verify name
@monthly.name
#=> 'Identity Plus'

## Verify amount (in cents)
@monthly.amount
#=> '1200'

## Verify currency
@monthly.currency
#=> 'usd'

## Verify entitlements were loaded
@monthly.entitlements.size
#=> 7

## Verify entitlements include expected values
@monthly.entitlements.member?('create_secrets')
#=> true

## Verify entitlements include custom_domains
@monthly.entitlements.member?('custom_domains')
#=> true

## Verify limits were loaded
@monthly.limits_hash.keys.sort
#=> ["custom_domains.max", "members_per_team.max", "secret_lifetime.max", "teams.max"]

## Verify unlimited custom_domains limit
@monthly.limits_hash['custom_domains.max']
#=> Float::INFINITY

## Verify members_per_team limit
@monthly.limits_hash['members_per_team.max']
#=> 10

## Verify yearly plan exists
@yearly = Billing::Plan.load('identity_plus_v1_yearly')
@yearly.nil?
#=> false

## Verify yearly plan attributes
@yearly.plan_id
#=> 'identity_plus_v1_yearly'

## Verify yearly interval
@yearly.interval
#=> 'year'

## Verify yearly amount
@yearly.amount
#=> '12000'

## Verify get_plan works with tier/interval/region
@plan_via_get = Billing::Plan.get_plan('single_team', 'monthly', 'EU')
@plan_via_get.plan_id
#=> 'identity_plus_v1_monthly'

## Test clearing and reloading (clear_first: false)
@before_count = Billing::Plan.instances.size
@reload_count = Billing::Plan.load_all_from_config(clear_first: false)
@after_count  = Billing::Plan.instances.size
[@before_count, @reload_count, @after_count]
#=> [2, 2, 2]

## Test clearing and reloading (clear_first: true, default)
@reload_count = Billing::Plan.load_all_from_config
@reload_count
#=> 2

## Verify instances were updated after reload
Billing::Plan.instances.size
#=> 2

## Teardown: Clear cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Teardown: Restore billing state
BillingTestHelpers.cleanup_billing_state!
true
#=> true

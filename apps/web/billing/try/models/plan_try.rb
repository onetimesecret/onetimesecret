# apps/web/billing/try/models/plan_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

# Billing Plan tests
#
# Tests Stripe plan data caching, refresh, and retrieval.
# Uses mock Stripe API responses to avoid external dependencies.
#
# Design note: Plans are family-keyed (e.g., "identity_v1") with
# interval variants stored in a nested `prices` hashkey.

## Setup: Load billing models
require 'apps/web/billing/models/plan'

## Setup: Enable billing for these plan cache tests
BillingTestHelpers.restore_billing!(enabled: true)

## Clear any existing plan cache
Billing::Plan.clear_cache.class
#=> Integer

## Create a mock plan manually (family-keyed, no interval suffix)
@plan = Billing::Plan.new(
  plan_id: 'identity_v1',
  stripe_product_id: 'prod_test123',
  name: 'Single Team',
  tier: 'single_team',
  currency: 'cad',
  region: 'us-east',
)
@plan.entitlements.add('api_access')
@plan.entitlements.add('manage_teams')
@plan.features.add('Feature 1')
@plan.features.add('Feature 2')
@plan.limits['teams.max'] = '1'
@plan.limits['members_per_team.max'] = '10'
# Add monthly price to prices hashkey
@plan.prices['month'] = { stripe_price_id: 'price_test123', amount: '2900', currency: 'cad' }.to_json
@plan.save
#=> true

## Verify plan was saved
Billing::Plan.instances.size
#=> 1

## Retrieve plan by ID (family-keyed)
@retrieved = Billing::Plan.load('identity_v1')
@retrieved.tier
#=> 'single_team'

## Get features as array
@retrieved.features.to_a.sort
#=> ["Feature 1", "Feature 2"]

## Get limits as hash (sorted for stable comparison)
@retrieved.limits_hash.sort.to_h
#=> {"members_per_team.max"=>10, "teams.max"=>1}

## Get plan using tier, interval, region
@plan_via_get = Billing::Plan.get_plan('single_team', 'monthly', 'us-east')
@plan_via_get.plan_id
#=> 'identity_v1'

## Access monthly price data via price_for
@price_data = @plan_via_get.price_for(:month)
@price_data[:amount]
#=> '2900'

## Add yearly price to existing plan (same family)
@retrieved.prices['year'] = { stripe_price_id: 'price_yearly123', amount: '29000', currency: 'cad' }.to_json
@retrieved.save
#=> true

## Verify plan now has both intervals (reload from Redis)
@refreshed = Billing::Plan.load('identity_v1')
@refreshed.available_intervals.sort
#=> [:month, :year]

## Get yearly price data
@yearly_price = @refreshed.price_for(:year)
@yearly_price[:amount]
#=> '29000'

## Get plan with yearly interval (same plan returned, different price)
@yearly_via_get = Billing::Plan.get_plan('single_team', 'yearly', 'us-east')
@yearly_via_get.plan_id
#=> 'identity_v1'

## List all plans (still just 1 family)
Billing::Plan.list_plans.size
#=> 1

## Clear cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

## Teardown: Restore billing state
BillingTestHelpers.cleanup_billing_state!
true
#=> true

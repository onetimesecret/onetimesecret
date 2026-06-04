# apps/web/billing/try/models/plan_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

# Billing Plan tests
#
# Tests Stripe plan data caching, refresh, and retrieval.
# Plans are keyed by canonical family ID with nested per-interval prices.

## Setup: Load billing models
require 'apps/web/billing/models/plan'

## Setup: Enable billing for these plan cache tests
BillingTestHelpers.restore_billing!(enabled: true)

## Clear any existing plan cache
Billing::Plan.clear_cache.class
#=> Integer

## Create a plan with canonical family ID and nested prices
@plan = Billing::Plan.new(
  plan_id: 'identity_plus_v1',
  stripe_product_id: 'prod_test123',
  name: 'Identity Plus',
  tier: 'single_team',
  currency: 'cad',
  region: 'us-east',
)
@plan.entitlements.add('api_access')
@plan.entitlements.add('manage_teams')
@plan.features.add('Feature 1')
@plan.features.add('Feature 2')
@plan.limits['teams.max'] = '1'
@plan.limits['total_members_per_org.max'] = '10'
# Add prices to hashkey (stored as JSON strings)
@plan.prices['month'] = { stripe_price_id: 'price_monthly123', amount: '2900', currency: 'cad' }.to_json
@plan.prices['year'] = { stripe_price_id: 'price_yearly123', amount: '29000', currency: 'cad' }.to_json
@plan.save
#=> true

## Verify plan was saved
Billing::Plan.instances.size
#=> 1

## Retrieve plan by canonical family ID
@retrieved = Billing::Plan.load('identity_plus_v1')
@retrieved.tier
#=> 'single_team'

## Get features as array
@retrieved.features.to_a.sort
#=> ["Feature 1", "Feature 2"]

## Get limits as hash (sorted for stable comparison)
@retrieved.limits_hash.sort.to_h
#=> {"total_members_per_org.max"=>10, "teams.max"=>1}

## Get available intervals
@retrieved.available_intervals.sort
#=> ['month', 'year']

## Get monthly price data via price_for
@monthly_price = @retrieved.price_for('month')
@monthly_price['amount']
#=> '2900'

## Get yearly price data via price_for
@yearly_price = @retrieved.price_for('year')
@yearly_price['amount']
#=> '29000'

## Get plan using tier, interval, region
@found_plan = Billing::Plan.get_plan('single_team', 'month', 'us-east')
@found_plan&.plan_id
#=> 'identity_plus_v1'

## Get plan with yearly interval (same plan returned)
@yearly_via_get = Billing::Plan.get_plan('single_team', 'year', 'us-east')
@yearly_via_get&.plan_id
#=> 'identity_plus_v1'

## List all plans (just 1 family)
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

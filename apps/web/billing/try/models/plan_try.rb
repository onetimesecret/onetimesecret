# apps/web/billing/try/models/plan_try.rb
#
# frozen_string_literal: true

require_relative '../../../../../try/support/test_helpers'

# Billing Plan tests
#
# Tests Stripe plan data caching, refresh, and retrieval.
# Uses mock Stripe API responses to avoid external dependencies.

## Setup: Load billing models
require 'apps/web/billing/models/plan'

## Clear any existing plan cache
Billing::Plan.clear_cache.class
#=> Integer

## Create a mock plan manually (metadata-based plan_id with interval)
@plan = Billing::Plan.new(
  plan_id: 'identity_v1_monthly',
  stripe_price_id: 'price_test123',
  stripe_product_id: 'prod_test123',
  name: 'Single Team',
  tier: 'single_team',
  interval: 'month',
  amount: '2900',
  currency: 'usd',
  region: 'us-east',
)
@plan.capabilities.add('create_secrets')
@plan.capabilities.add('create_team')
@plan.features.add('Feature 1')
@plan.features.add('Feature 2')
@plan.limits['teams.max'] = '1'
@plan.limits['members_per_team.max'] = '10'
@plan.save
#=> true

## Verify plan was saved
Billing::Plan.instances.size
#=> 1

## Retrieve plan by ID (metadata-based with interval)
@retrieved = Billing::Plan.load('identity_v1_monthly')
@retrieved.tier
#=> 'single_team'

## Get features as array
@retrieved.features.to_a.sort
#=> ["Feature 1", "Feature 2"]

## Get limits as hash (sorted for stable comparison)
@retrieved.limits_hash.sort.to_h
#=> {"members_per_team.max"=>10, "teams.max"=>1}

## Get plan using tier, interval, region
@monthly_plan = Billing::Plan.get_plan('single_team', 'monthly', 'us-east')
@monthly_plan.plan_id
#=> 'identity_v1_monthly'

## Get plan with yearly interval (different plan_id for yearly)
@yearly_plan = Billing::Plan.new(
  plan_id: 'identity_v1_yearly',
  stripe_price_id: 'price_yearly123',
  stripe_product_id: 'prod_test123',
  name: 'Single Team Annual',
  tier: 'single_team',
  interval: 'year',
  amount: '29000',
  currency: 'usd',
  region: 'us-east',
)
@yearly_plan.capabilities.add('create_secrets')
@yearly_plan.capabilities.add('create_team')
@yearly_plan.features.add('Feature 1')
@yearly_plan.features.add('Feature 2')
@yearly_plan.limits['teams.max'] = '1'
@yearly_plan.limits['members_per_team.max'] = '10'
@yearly_plan.save
@yearly_retrieved = Billing::Plan.get_plan('single_team', 'yearly', 'us-east')
@yearly_retrieved.plan_id
#=> 'identity_v1_yearly'

## List all plans
Billing::Plan.list_plans.size
#=> 2

## Clear cache
Billing::Plan.clear_cache
Billing::Plan.instances.size
#=> 0

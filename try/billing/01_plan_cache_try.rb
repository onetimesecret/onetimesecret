require_relative '../support/test_helpers'

# Billing PlanCache tests
#
# Tests Stripe plan data caching, refresh, and retrieval.
# Uses mock Stripe API responses to avoid external dependencies.

## Setup: Load billing models
require 'apps/web/billing/models/plan_cache'

## Clear any existing plan cache
Billing::Models::PlanCache.clear_cache.class
#=> Integer

## Create a mock plan manually
@plan = Billing::Models::PlanCache.new(
  plan_id: 'single_team_monthly_us-east',
  stripe_price_id: 'price_test123',
  stripe_product_id: 'prod_test123',
  name: 'Single Team',
  tier: 'single_team',
  interval: 'month',
  amount: '2900',
  currency: 'usd',
  region: 'us-east',
  features: '["Feature 1", "Feature 2"]',
  limits: '{"teams": 1, "members_per_team": 10}'
)
@plan.save
#=> true

## Verify plan was saved
Billing::Models::PlanCache.values.size
#=> 1

## Retrieve plan by ID
@retrieved = Billing::Models::PlanCache.load('single_team_monthly_us-east')
@retrieved.tier
#=> 'single_team'

## Parse JSON fields
@retrieved.parsed_features
#=> ["Feature 1", "Feature 2"]

## Parse limits
@retrieved.parsed_limits
#=> {"teams"=>1, "members_per_team"=>10}

## Get plan using tier, interval, region
@monthly_plan = Billing::Models::PlanCache.get_plan('single_team', 'monthly', 'us-east')
@monthly_plan.plan_id
#=> 'single_team_monthly_us-east'

## Get plan with yearly interval
@yearly_plan = Billing::Models::PlanCache.new(
  plan_id: 'single_team_yearly_us-east',
  stripe_price_id: 'price_yearly123',
  stripe_product_id: 'prod_test123',
  name: 'Single Team Annual',
  tier: 'single_team',
  interval: 'year',
  amount: '29000',
  currency: 'usd',
  region: 'us-east',
  features: '["Feature 1", "Feature 2"]',
  limits: '{"teams": 1, "members_per_team": 10}'
)
@yearly_plan.save
@yearly_retrieved = Billing::Models::PlanCache.get_plan('single_team', 'yearly', 'us-east')
@yearly_retrieved.interval
#=> 'year'

## List all plans
Billing::Models::PlanCache.list_plans.size
#=> 2

## Clear cache
Billing::Models::PlanCache.clear_cache
Billing::Models::PlanCache.values.size
#=> 0

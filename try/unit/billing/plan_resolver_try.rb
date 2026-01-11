# apps/web/billing/lib/plan_resolver_try.rb
#
# Tryouts for Billing::PlanResolver
#
# Tests plan resolution from URL params to checkout params.
#
# Run: bundle exec try apps/web/billing/lib/plan_resolver_try.rb

require_relative '../../support/test_helpers'
require_relative '../../../apps/web/billing/models/plan'
require_relative '../../../apps/web/billing/lib/plan_resolver'

# Setup
@plan_loaded = false

def setup_test_plan
  return if @plan_loaded

  # Create a test plan in the cache
  plan = Billing::Plan.new(
    plan_id: 'identity_plus_v1_monthly',
    stripe_price_id: 'price_test_identity_monthly',
    stripe_product_id: 'prod_test_identity',
    name: 'Identity Plus',
    tier: 'identity',
    interval: 'month',
    amount: '1500',
    currency: 'usd',
    region: 'global'
  )
  plan.active = 'true'
  plan.save

  # Also create yearly variant
  yearly_plan = Billing::Plan.new(
    plan_id: 'identity_plus_v1_yearly',
    stripe_price_id: 'price_test_identity_yearly',
    stripe_product_id: 'prod_test_identity',
    name: 'Identity Plus',
    tier: 'identity',
    interval: 'year',
    amount: '15000',
    currency: 'usd',
    region: 'global'
  )
  yearly_plan.active = 'true'
  yearly_plan.save

  @plan_loaded = true
end

# Teardown
def teardown_test_plan
  %w[identity_plus_v1_monthly identity_plus_v1_yearly].each do |plan_id|
    plan = Billing::Plan.load(plan_id)
    plan&.destroy! if plan&.exists?
  end
  @plan_loaded = false
end

setup_test_plan

## Resolve returns success for valid plan
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.success?
#=> true

## Resolve returns correct plan_id
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.plan_id
#=> 'identity_plus_v1_monthly'

## Resolve returns correct tier
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.tier
#=> 'identity'

## Resolve returns correct billing_cycle
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.billing_cycle
#=> 'monthly'

## Resolve handles yearly interval
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'yearly')
[result.success?, result.plan_id, result.billing_cycle]
#=> [true, 'identity_plus_v1_yearly', 'yearly']

## Resolve normalizes month to monthly
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'month')
result.billing_cycle
#=> 'monthly'

## Resolve normalizes year to yearly
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'year')
result.billing_cycle
#=> 'yearly'

## Resolve normalizes annual to yearly
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'annual')
result.billing_cycle
#=> 'yearly'

## Resolve returns failure for missing product
result = Billing::PlanResolver.resolve(product: nil, interval: 'monthly')
[result.success?, result.error]
#=> [false, 'Missing product']

## Resolve returns failure for missing interval
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: nil)
[result.success?, result.error]
#=> [false, 'Missing interval']

## Resolve returns failure for invalid interval
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'weekly')
[result.success?, result.error.include?('Invalid interval')]
#=> [false, true]

## Resolve returns failure for unknown plan
result = Billing::PlanResolver.resolve(product: 'unknown_plan', interval: 'monthly')
[result.success?, result.error.include?('Plan not found')]
#=> [false, true]

## valid_params? returns true for valid params
Billing::PlanResolver.valid_params?(product: 'any_product', interval: 'monthly')
#=> true

## valid_params? returns false for missing product
Billing::PlanResolver.valid_params?(product: nil, interval: 'monthly')
#=> false

## valid_params? returns false for missing interval
Billing::PlanResolver.valid_params?(product: 'product', interval: nil)
#=> false

## valid_params? returns false for invalid interval
Billing::PlanResolver.valid_params?(product: 'product', interval: 'weekly')
#=> false

## checkout_params returns hash for successful resolution
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
params = result.checkout_params
[params[:tier], params[:billing_cycle]]
#=> ['identity', 'monthly']

## checkout_params returns nil for failed resolution
result = Billing::PlanResolver.resolve(product: 'unknown', interval: 'monthly')
result.checkout_params
#=> nil

## checkout_url generates correct path
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.checkout_url('org_abc123')
#=> '/billing/api/org/org_abc123/checkout'

## checkout_url returns nil for failed resolution
result = Billing::PlanResolver.resolve(product: 'unknown', interval: 'monthly')
result.checkout_url('org_abc123')
#=> nil

teardown_test_plan

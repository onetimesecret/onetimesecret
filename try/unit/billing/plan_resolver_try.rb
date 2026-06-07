# try/unit/billing/plan_resolver_try.rb
#
# frozen_string_literal: true

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

  # Plans are now family-keyed with interval variants nested in `prices`.
  plan = Billing::Plan.new(
    plan_id: 'identity_plus_v1',
    stripe_product_id: 'prod_test_identity',
    name: 'Identity Plus',
    tier: 'identity',
    currency: 'cad',
    region: 'global'
  )
  plan.active = 'true'
  plan.save

  monthly_data = {
    stripe_price_id: 'price_test_identity_monthly',
    amount: '1500',
    currency: 'cad',
    active: 'true',
  }
  yearly_data = {
    stripe_price_id: 'price_test_identity_yearly',
    amount: '15000',
    currency: 'cad',
    active: 'true',
  }
  plan.prices['month'] = monthly_data.to_json
  plan.prices['year']  = yearly_data.to_json
  plan.instance_variable_set(:@prices_hash, nil)

  @plan_loaded = true
end

# Teardown
def teardown_test_plan
  plan = Billing::Plan.load('identity_plus_v1')
  plan&.destroy! if plan&.exists?
  @plan_loaded = false
end

setup_test_plan

## Resolve returns success for valid plan
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.success?
#=> true

## Resolve returns family-keyed plan_id (no interval suffix)
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.plan_id
#=> 'identity_plus_v1'

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
#=> [true, 'identity_plus_v1', 'yearly']

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

## Resolve handles annually variant
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'annually')
result.billing_cycle
#=> 'yearly'

## Resolve normalizes uppercase intervals
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'MONTHLY')
result.billing_cycle
#=> 'monthly'

## Resolve normalizes mixed case intervals
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'Yearly')
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

## Resolve handles empty string product
result = Billing::PlanResolver.resolve(product: '  ', interval: 'monthly')
[result.success?, result.error]
#=> [false, 'Missing product']

## Resolve handles empty string interval
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: '')
[result.success?, result.error]
#=> [false, 'Missing interval']

## Resolve returns failure for invalid interval
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'weekly')
[result.success?, result.error.include?('Invalid interval')]
#=> [false, true]

## Resolve returns failure for interval-suffixed plan ID
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1_monthly', interval: 'monthly')
[result.success?, result.error.include?('Invalid plan ID format')]
#=> [false, true]

## Resolve returns failure for uppercase plan ID
result = Billing::PlanResolver.resolve(product: 'Identity_Plus_V1', interval: 'monthly')
[result.success?, result.error.include?('Invalid plan ID format')]
#=> [false, true]

## Resolve returns failure for unknown plan (with valid canonical format)
result = Billing::PlanResolver.resolve(product: 'unknown_plan_v1', interval: 'monthly')
[result.success?, result.error.include?('Plan not found')]
#=> [false, true]

## Result failed? returns true for failed resolution
result = Billing::PlanResolver.resolve(product: 'unknown_v1', interval: 'monthly')
result.failed?
#=> true

## Result failed? returns false for successful resolution
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.failed?
#=> false

## valid_params? returns true for valid params (canonical format)
Billing::PlanResolver.valid_params?(product: 'any_product_v1', interval: 'monthly')
#=> true

## valid_params? returns false for missing product
Billing::PlanResolver.valid_params?(product: nil, interval: 'monthly')
#=> false

## valid_params? returns false for missing interval
Billing::PlanResolver.valid_params?(product: 'product_v1', interval: nil)
#=> false

## valid_params? returns false for invalid interval
Billing::PlanResolver.valid_params?(product: 'product_v1', interval: 'weekly')
#=> false

## valid_params? returns false for non-canonical plan ID (suffixed)
Billing::PlanResolver.valid_params?(product: 'identity_plus_v1_monthly', interval: 'monthly')
#=> false

## valid_params? returns false for non-canonical plan ID (uppercase)
Billing::PlanResolver.valid_params?(product: 'Identity_Plus_V1', interval: 'monthly')
#=> false

## canonical_plan_id? rejects plan ID starting with digit
Billing::PlanResolver.canonical_plan_id?('1identity_v1')
#=> false

## canonical_plan_id? accepts minimal valid ID (single char before version)
Billing::PlanResolver.canonical_plan_id?('a_v1')
#=> true

## canonical_plan_id? accepts numeric segments after underscore
Billing::PlanResolver.canonical_plan_id?('plan_123_v1')
#=> true

## canonical_plan_id? rejects double underscores
Billing::PlanResolver.canonical_plan_id?('plan__v1')
#=> false

## canonical_plan_id? rejects trailing underscore without version
Billing::PlanResolver.canonical_plan_id?('plan_')
#=> false

## canonical_plan_id? rejects missing version suffix
Billing::PlanResolver.canonical_plan_id?('identity_plus')
#=> false

## canonical_plan_id? rejects version without underscore
Billing::PlanResolver.canonical_plan_id?('planv1')
#=> false

## canonical_plan_id? accepts version zero
Billing::PlanResolver.canonical_plan_id?('plan_v0')
#=> true

## canonical_plan_id? accepts multi-digit version
Billing::PlanResolver.canonical_plan_id?('plan_v999')
#=> true

## canonical_plan_id? rejects hyphens
Billing::PlanResolver.canonical_plan_id?('identity-plus-v1')
#=> false

## canonical_plan_id? rejects dots
Billing::PlanResolver.canonical_plan_id?('identity.plus.v1')
#=> false

## canonical_plan_id? rejects embedded spaces
Billing::PlanResolver.canonical_plan_id?('plan v1')
#=> false

## canonical_plan_id? rejects unicode characters
Billing::PlanResolver.canonical_plan_id?('plan_火_v1')
#=> false

## canonical_plan_id? rejects yearly suffix variant
Billing::PlanResolver.canonical_plan_id?('identity_plus_v1_yearly')
#=> false

## canonical_plan_id? rejects _month suffix (Stripe interval format)
Billing::PlanResolver.canonical_plan_id?('identity_plus_v1_month')
#=> false

## canonical_plan_id? rejects _year suffix (Stripe interval format)
Billing::PlanResolver.canonical_plan_id?('identity_plus_v1_year')
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

## checkout_url handles org_extid with underscores
result = Billing::PlanResolver.resolve(product: 'identity_plus_v1', interval: 'monthly')
result.checkout_url('org_abc_123_def')
#=> '/billing/api/org/org_abc_123_def/checkout'

teardown_test_plan

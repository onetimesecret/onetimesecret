# try/unit/auth/billing_hooks_try.rb
#
# frozen_string_literal: true

# Tests the billing hooks that capture plan selection during auth flows
# and build billing redirect info for JSON responses.
#
# Run: bundle exec try try/unit/auth/billing_hooks_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

OT.boot! :test, false

require_relative '../../../apps/web/billing/lib/plan_resolver'

# MockRodauthInstance simulates Rodauth context for testing hook methods
#
# The billing hooks define methods on Rodauth instances via define_method.
# This mock provides the minimal interface needed to test those methods.
class MockRodauthInstance
  attr_reader :session, :json_response, :params

  def initialize(params: {}, session: {}, json_response: {})
    @params = params
    @session = session
    @json_response = json_response
  end

  # Simulates Rodauth's param_or_nil method
  def param_or_nil(key)
    val = @params[key]
    val.nil? || val.to_s.strip.empty? ? nil : val
  end

  # Capture plan selection from params into session
  # Mirrors the logic from Auth::Config::Hooks::Billing.define_capture_method
  def capture_plan_selection
    product  = param_or_nil('product')
    interval = param_or_nil('interval')
    return unless product || interval
    session[:billing_product]  = product  if product
    session[:billing_interval] = interval if interval
  end

  # Build billing redirect info for JSON response
  # Mirrors the logic from Auth::Config::Hooks::Billing.define_build_method
  def build_billing_redirect_info(product, interval, billing_enabled: true)
    unless billing_enabled
      return { product: product, interval: interval, valid: false, error: 'Billing not enabled' }
    end
    unless product && interval
      return { product: product, interval: interval, valid: false, error: 'Missing product or interval' }
    end
    result = ::Billing::PlanResolver.resolve(product: product, interval: interval)
    if result.success?
      { product: product, interval: interval, valid: true }
    else
      { product: product, interval: interval, valid: false, error: result.error }
    end
  end
end

# Create test plans in Redis for validation tests
@plans_created = false

def setup_test_plans
  return if @plans_created

  BillingTestHelpers.ensure_familia_configured!

  # Create test plans for PlanResolver validation
  plan = Billing::Plan.new(
    plan_id: 'identity_plus_v1_monthly',
    stripe_price_id: 'price_test_identity_monthly',
    stripe_product_id: 'prod_test_identity',
    name: 'Identity Plus',
    tier: 'identity',
    interval: 'month',
    amount: '1500',
    currency: 'cad',
    region: 'global'
  )
  plan.active = 'true'
  plan.save

  yearly_plan = Billing::Plan.new(
    plan_id: 'identity_plus_v1_yearly',
    stripe_price_id: 'price_test_identity_yearly',
    stripe_product_id: 'prod_test_identity',
    name: 'Identity Plus',
    tier: 'identity',
    interval: 'year',
    amount: '15000',
    currency: 'cad',
    region: 'global'
  )
  yearly_plan.active = 'true'
  yearly_plan.save

  @plans_created = true
end

def teardown_test_plans
  %w[identity_plus_v1_monthly identity_plus_v1_yearly].each do |plan_id|
    plan = Billing::Plan.load(plan_id)
    plan&.destroy! if plan&.exists?
  end
  @plans_created = false
end

# Helper to check billing_enabled? logic with a given config hash
def billing_enabled_with_config?(config)
  config&.dig('enabled').to_s == 'true'
end

# ============================================================================
# capture_plan_selection tests
# ============================================================================

## capture_plan_selection stores product in session
instance = MockRodauthInstance.new(
  params: { 'product' => 'identity_plus_v1', 'interval' => 'monthly' }
)
instance.capture_plan_selection
instance.session[:billing_product]
#=> 'identity_plus_v1'

## capture_plan_selection stores interval in session
instance = MockRodauthInstance.new(
  params: { 'product' => 'identity_plus_v1', 'interval' => 'monthly' }
)
instance.capture_plan_selection
instance.session[:billing_interval]
#=> 'monthly'

## capture_plan_selection handles nil params gracefully
instance = MockRodauthInstance.new(
  params: { 'product' => nil, 'interval' => nil }
)
instance.capture_plan_selection
[instance.session[:billing_product], instance.session[:billing_interval]]
#=> [nil, nil]

## capture_plan_selection handles empty string params
instance = MockRodauthInstance.new(
  params: { 'product' => '', 'interval' => '   ' }
)
instance.capture_plan_selection
[instance.session[:billing_product], instance.session[:billing_interval]]
#=> [nil, nil]

## capture_plan_selection stores product only when interval missing
instance = MockRodauthInstance.new(
  params: { 'product' => 'identity_plus_v1' }
)
instance.capture_plan_selection
[instance.session[:billing_product], instance.session[:billing_interval]]
#=> ['identity_plus_v1', nil]

# ============================================================================
# build_billing_redirect_info tests
# ============================================================================

setup_test_plans
BillingTestHelpers.restore_billing!(enabled: true)

## build_billing_redirect_info returns valid structure for good params
instance = MockRodauthInstance.new
info = instance.build_billing_redirect_info('identity_plus_v1', 'monthly', billing_enabled: true)
[info[:product], info[:interval], info[:valid]]
#=> ['identity_plus_v1', 'monthly', true]

## build_billing_redirect_info returns error for missing product
instance = MockRodauthInstance.new
info = instance.build_billing_redirect_info(nil, 'monthly', billing_enabled: true)
[info[:valid], info[:error]]
#=> [false, 'Missing product or interval']

## build_billing_redirect_info returns error for missing interval
instance = MockRodauthInstance.new
info = instance.build_billing_redirect_info('identity_plus_v1', nil, billing_enabled: true)
[info[:valid], info[:error]]
#=> [false, 'Missing product or interval']

## build_billing_redirect_info validates plan exists via PlanResolver
instance = MockRodauthInstance.new
info = instance.build_billing_redirect_info('unknown_plan', 'monthly', billing_enabled: true)
[info[:valid], info[:error].include?('Plan not found')]
#=> [false, true]

## build_billing_redirect_info returns error when billing disabled
instance = MockRodauthInstance.new
info = instance.build_billing_redirect_info('identity_plus_v1', 'monthly', billing_enabled: false)
[info[:valid], info[:error]]
#=> [false, 'Billing not enabled']

# ============================================================================
# billing_enabled? tests
#
# Tests the config parsing logic used by billing_enabled? method.
# Uses a helper function instead of modifying frozen Onetime.conf.
# ============================================================================

## billing_enabled? returns true when config enabled with string 'true'
billing_enabled_with_config?({ 'enabled' => 'true' })
#=> true

## billing_enabled? returns false when config enabled with string 'false'
billing_enabled_with_config?({ 'enabled' => 'false' })
#=> false

## billing_enabled? returns false when config is nil
billing_enabled_with_config?(nil)
#=> false

## billing_enabled? returns false when enabled key is missing
billing_enabled_with_config?({})
#=> false

## billing_enabled? handles boolean true (not string)
billing_enabled_with_config?({ 'enabled' => true })
#=> true

## billing_enabled? handles boolean false (not string)
billing_enabled_with_config?({ 'enabled' => false })
#=> false

# Teardown
teardown_test_plans
BillingTestHelpers.cleanup_billing_state!

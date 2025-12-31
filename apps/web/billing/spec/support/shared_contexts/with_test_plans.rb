# apps/web/billing/spec/support/shared_contexts/with_test_plans.rb
#
# frozen_string_literal: true

# Shared context for loading test plans for billing specs
#
# Purpose: Enable unit testing of billing logic without Stripe API access.
# ConfigResolver finds apps/web/billing/spec/billing.test.yaml in test env.
#
# Usage:
#   RSpec.describe 'BillingController' do
#     include_context 'with_test_plans'
#
#     it 'loads plans from test config' do
#       plans = Billing::Plan.list_plans_from_config
#       expect(plans).not_to be_empty
#     end
#   end
#
# Note: The test config has enabled: false by default for test isolation.
# This context explicitly enables billing for tests that need it.
#
RSpec.shared_context 'with_test_plans' do
  before do
    # Enable billing for tests that need it
    # The test config has enabled: false by default for isolation
    allow(Onetime::BillingConfig.instance).to receive(:enabled?).and_return(true)

    # Load all plans from test config into Redis cache
    Billing::Plan.load_all_from_config

    # Mock region to match test plans (EU)
    mock_region!('EU')
  end

  after do
    # Clean up Redis cache
    Billing::Plan.clear_cache

    # Reset BillingConfig stubs
    RSpec::Mocks.space.proxy_for(Onetime::BillingConfig.instance).reset
  end

  # Helper: Get test plan by tier
  #
  # @param tier [String] Plan tier (e.g., 'single_team', 'free')
  # @param interval [String] Billing interval ('monthly' or 'yearly', defaults to 'monthly')
  # @return [Hash, nil] Plan hash from config or nil
  def test_plan(tier, interval = 'monthly')
    # Normalize interval
    interval_normalized = interval.to_s.sub(/ly$/, '')

    # Load all plans from config
    plans = Billing::Plan.list_plans_from_config

    # Find matching plan
    plans.find do |plan|
      plan[:tier] == tier &&
        (plan[:planid].include?("_#{interval_normalized}ly") || !plan[:planid].include?('_monthly') && !plan[:planid].include?('_yearly'))
    end
  end

  # Helper: Get test plan ID for tier/interval/region
  #
  # @param tier [String] Plan tier
  # @param interval [String] Billing interval ('monthly' or 'yearly')
  # @param region [String] Region code (defaults to 'EU')
  # @return [String] Plan ID in format: tier_region_interval
  def test_plan_id(tier, interval = 'monthly', region = 'EU')
    "#{tier}_#{region}_#{interval}".downcase
  end

  # Helper: Load test entitlements from config
  #
  # @return [Hash] Entitlements from billing.test.yaml
  def test_entitlements
    Billing::Config.load_entitlements
  end

  # Helper: Check if test plan exists
  #
  # @param tier [String] Plan tier
  # @param interval [String] Billing interval (defaults to 'monthly')
  # @return [Boolean]
  def test_plan_exists?(tier, interval = 'monthly')
    !test_plan(tier, interval).nil?
  end
end

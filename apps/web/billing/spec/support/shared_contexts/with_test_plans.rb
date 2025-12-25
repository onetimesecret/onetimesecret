# apps/web/billing/spec/support/shared_contexts/with_test_plans.rb
#
# frozen_string_literal: true

# Shared context for loading test plans from spec/billing.test.yaml
#
# Purpose: Enable unit testing of billing logic without Stripe API access.
# Uses ConfigResolver to load test plans from spec/billing.test.yaml.
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
# Note: This context populates Redis cache using Plan.load_all_from_config
# which loads plans from spec/billing.test.yaml into Redis for testing.
#
RSpec.shared_context 'with_test_plans' do
  # Ensure Billing::Config uses test config file
  before do
    # ConfigResolver automatically uses spec/billing.test.yaml when RACK_ENV=test
    # No mocking needed - just verify the file exists
    test_config_path = File.join(Onetime::HOME, 'spec', 'billing.test.yaml')
    unless File.exist?(test_config_path)
      raise "Test config missing: #{test_config_path}"
    end

    # Load all plans from test config into Redis cache
    # This populates the cache with plans from spec/billing.test.yaml
    Billing::Plan.load_all_from_config

    # Mock region to match test plans (EU)
    mock_region!('EU')
  end

  after do
    # Clean up Redis cache
    Billing::Plan.clear_cache
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

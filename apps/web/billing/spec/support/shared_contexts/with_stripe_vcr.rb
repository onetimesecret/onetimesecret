# apps/web/billing/spec/support/shared_contexts/with_stripe_vcr.rb
#
# frozen_string_literal: true

# Shared context for Stripe API integration tests with VCR
#
# Purpose: Encapsulate VCR setup for tests that make real Stripe API calls.
# Ensures plan cache is populated and region is configured correctly.
#
# Usage:
#   RSpec.describe 'BillingController', :integration do
#     include Rack::Test::Methods
#     include_context 'with_stripe_vcr'
#     include_context 'with_authenticated_customer'
#     include_context 'with_organization'
#
#     it 'creates checkout session', :vcr do
#       post "/billing/api/org/#{organization.extid}/checkout", {
#         tier: 'single_team',
#         billing_cycle: 'monthly'
#       }.to_json, { 'CONTENT_TYPE' => 'application/json' }
#
#       expect(last_response.status).to eq(200)
#     end
#   end
#
# Provides:
#   - Stripe plan cache refresh from API
#   - Region mocking (defaults to 'EU' to match test Stripe plans)
#   - VCR cassette wrapping (automatic via billing_spec_helper.rb)
#
# Requirements:
#   - Test must be tagged with :vcr
#   - STRIPE_API_KEY must be set for recording new cassettes
#   - Existing cassettes must exist for playback mode
#
RSpec.shared_context 'with_stripe_vcr' do
  before do
    # Mock region to match Stripe plan metadata (EU is default test region)
    mock_region!('EU')

    # Refresh plan cache from Stripe API (uses VCR cassette)
    # Only runs if STRIPE_API_KEY is configured
    if ENV['STRIPE_API_KEY']
      Billing::Plan.refresh_from_stripe
    else
      OT.lw '[with_stripe_vcr] Skipping plan refresh: No STRIPE_API_KEY'
    end
  end

  # Helper: Get cached plan from Redis
  #
  # Retrieves plan from Stripe-synced Redis cache (not config fallback).
  #
  # @param tier [String] Plan tier
  # @param interval [String] Billing interval ('monthly' or 'yearly')
  # @param region [String] Region code (defaults to 'EU')
  # @return [Billing::Plan, nil]
  def cached_stripe_plan(tier, interval = 'monthly', region = 'EU')
    Billing::Plan.get_plan(tier, interval, region)
  end

  # Helper: Verify plan exists in cache
  #
  # @param tier [String] Plan tier
  # @param interval [String] Billing interval
  # @param region [String] Region code (defaults to 'EU')
  # @return [Boolean]
  def cached_plan_exists?(tier, interval = 'monthly', region = 'EU')
    !cached_stripe_plan(tier, interval, region).nil?
  end

  # Helper: Get Stripe price ID for plan
  #
  # @param tier [String] Plan tier
  # @param interval [String] Billing interval
  # @param region [String] Region code (defaults to 'EU')
  # @return [String, nil] Stripe price ID or nil
  def stripe_price_id_for(tier, interval = 'monthly', region = 'EU')
    plan = cached_stripe_plan(tier, interval, region)
    plan&.stripe_price_id
  end
end

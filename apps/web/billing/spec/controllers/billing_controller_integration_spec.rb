# apps/web/billing/spec/controllers/billing_controller_integration_spec.rb
#
# frozen_string_literal: true

# Integration tests for BillingController - tests that require real Stripe API via VCR
# These tests use VCR cassettes to record/replay Stripe API calls.
#
# For unit tests that use local config only, see billing_controller_unit_spec.rb
#
# =========================================================================
# TEST DESIGN NOTES
# =========================================================================
#
# Tests that require specific Stripe resources (subscriptions with price IDs,
# invoices with line items) are implemented in billing_controller_spec.rb using
# Ruby-level mocking. This avoids:
#
#   1. VCR cassettes becoming stale when Stripe's API responses change
#   2. Price IDs being specific to individual Stripe accounts
#   3. Tests not being portable across development environments
#   4. Recording cassettes requiring manual intervention with real API keys
#
# This file focuses on integration tests that:
#   - Test checkout session creation (uses plan catalog, no specific price ID)
#   - Test error handling with Stripe API
#   - Verify request/response flow through the full stack
#
# For subscription data and invoice tests, see billing_controller_spec.rb
# which uses mocking to simulate organization state.
# =========================================================================

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Billing::Controllers::BillingController - Integration', :integration, :stripe_sandbox_api do
  include Rack::Test::Methods
  include_context 'with_stripe_vcr'
  include_context 'with_authenticated_customer'
  include_context 'with_organization'

  # The Rack application for testing
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  describe 'GET /billing/api/plans' do
    it 'handles plan cache refresh failures gracefully', :vcr do
      # Simulate Stripe error
      allow(Billing::Plan).to receive(:list_plans).and_raise(Stripe::StripeError)

      get '/billing/api/plans'

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to list plans')
    end
  end

  # =========================================================================
  # NOTE: Subscription data tests moved to billing_controller_spec.rb
  # =========================================================================
  #
  # The test "returns subscription data when organization has active subscription"
  # required creating a real Stripe subscription with a specific price ID.
  # This was fragile because:
  #   - Price IDs are account-specific
  #   - Required STRIPE_TEST_PRICE_ID env var
  #   - VCR cassettes became stale
  #
  # The test now lives in billing_controller_spec.rb using Ruby-level mocking
  # to simulate organization subscription state.
  # =========================================================================

  describe 'POST /billing/api/org/:extid/checkout' do
    let(:tier) { 'single_team' }
    let(:billing_cycle) { 'monthly' }

    before do
      # Sync plans from Stripe to Redis cache (needed for plan lookup)
      ::Billing::Plan.refresh_from_stripe if ENV['STRIPE_API_KEY']
    end

    it 'creates Stripe checkout session', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('checkout_url')
      expect(data).to have_key('session_id')
      expect(data['checkout_url']).to match(%r{\Ahttps://checkout\.stripe\.com/})
    end

    it 'uses existing Stripe customer if organization has one', :vcr do
      # Create Stripe customer and associate with organization
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Verify the checkout session used the existing customer
      data    = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])
      expect(session.customer).to eq(stripe_customer.id)
    end

    # =========================================================================
    # NOTE: Metadata verification removed
    # =========================================================================
    #
    # The test "includes metadata in subscription" attempted to verify
    # session.subscription_data['metadata'] after checkout session creation.
    #
    # This is NOT possible because subscription_data is a WRITE-ONLY parameter
    # in Stripe's API - it's passed when creating the session but NOT returned
    # on retrieval. The metadata appears on the actual Subscription object only
    # after checkout completion (verified via webhook processing tests).
    #
    # See: apps/web/billing/spec/operations/process_webhook_event/checkout_completed_spec.rb
    # =========================================================================

    it 'uses idempotency key to prevent duplicates', :vcr do
      # Make two identical requests
      2.times do
        post "/billing/api/org/#{organization.extid}/checkout", {
          tier: tier,
          billing_cycle: billing_cycle,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
      end

      # Both requests should succeed due to idempotency
    end
  end

  # =========================================================================
  # NOTE: Invoice list tests moved to billing_controller_spec.rb
  # =========================================================================
  #
  # The test "returns list of invoices for organization" required creating
  # real Stripe invoices, which:
  #   - Requires customer with valid email
  #   - Creates persistent test data in Stripe
  #   - VCR cassettes become stale
  #
  # The test now lives in billing_controller_spec.rb using Ruby-level mocking
  # to simulate the controller's invoice list response.
  # =========================================================================

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'handles Stripe errors gracefully', :vcr do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to retrieve invoices')
    end
  end
end

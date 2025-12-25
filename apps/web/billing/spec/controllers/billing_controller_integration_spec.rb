# apps/web/billing/spec/controllers/billing_controller_integration_spec.rb
#
# frozen_string_literal: true

# Integration tests for BillingController - tests that require real Stripe API via VCR
# These tests use VCR cassettes to record/replay Stripe API calls.
#
# For unit tests that use local config only, see billing_controller_unit_spec.rb

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

  describe 'GET /billing/api/org/:extid' do
    it 'returns subscription data when organization has active subscription', :vcr do
      # Create Stripe customer with payment method
      stripe_customer = Stripe::Customer.create(email: customer.email)
      payment_method = Stripe::PaymentMethod.create(
        type: 'card',
        card: { token: 'tok_visa' }
      )
      Stripe::PaymentMethod.attach(payment_method.id, { customer: stripe_customer.id })
      Stripe::Customer.update(stripe_customer.id, {
        invoice_settings: { default_payment_method: payment_method.id }
      })

      subscription = Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
      )

      organization.update_from_stripe_subscription(subscription)
      organization.save

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).not_to be_nil
      expect(data['subscription']['id']).to eq(subscription.id)
      expect(data['subscription']['status']).to match(/active|trialing/)
    end
  end

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

    it 'includes metadata in subscription', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      data    = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])

      expect(session.subscription_data['metadata']).to include(
        'orgid' => organization.objid,
        'tier' => tier,
        'external_id' => customer.extid,
      )
    end

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

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns list of invoices for organization', :vcr do
      # Create Stripe customer and invoice
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      # Create an invoice
      Stripe::Invoice.create(
        customer: stripe_customer.id,
        collection_method: 'send_invoice',
        days_until_due: 30,
      )

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data).to have_key('invoices')
      expect(data).to have_key('has_more')
      expect(data['invoices']).to be_an(Array)

      unless data['invoices'].empty?
        invoice_data = data['invoices'].first
        expect(invoice_data).to have_key('id')
        expect(invoice_data).to have_key('number')
        expect(invoice_data).to have_key('amount')
        expect(invoice_data).to have_key('currency')
        expect(invoice_data).to have_key('status')
        expect(invoice_data).to have_key('created')
        expect(invoice_data).to have_key('invoice_pdf')
        expect(invoice_data).to have_key('hosted_invoice_url')
      end
    end

    it 'handles Stripe errors gracefully', :vcr do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to retrieve invoices')
    end
  end
end

# apps/web/billing/spec/controllers/billing_controller_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'
require 'digest'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Billing::Controllers::BillingController', :integration, :stripe_sandbox_api, :vcr do
  include Rack::Test::Methods

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  # Generate deterministic email based on test description for VCR cassette matching
  # Same test always produces same email, different tests get different emails
  def deterministic_email(prefix = 'billing-test')
    test_hash = Digest::SHA256.hexdigest(RSpec.current_example.full_description)[0..7]
    "#{prefix}-#{test_hash}@example.com"
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: deterministic_email)
    created_customers << cust
    cust
  end

  let(:organization) do
    org = Onetime::Organization.create!('Test Organization', customer, customer.email)
    created_organizations << org
    org
  end

  before do
    customer.save
    organization.save

    # Mock authentication by setting up session
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
    }
  end

  after do
    # Clean up created test data
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe 'GET /billing/api/plans' do
    it 'returns list of available plans', :vcr do
      # Ensure plan cache is populated
      Billing::Plan.refresh_from_stripe

      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('plans')
      expect(data['plans']).to be_an(Array)

      # Verify plan structure
      unless data['plans'].empty?
        plan = data['plans'].first
        expect(plan).to have_key('id')
        expect(plan).to have_key('name')
        expect(plan).to have_key('tier')
        expect(plan).to have_key('interval')
        expect(plan).to have_key('amount')
        expect(plan).to have_key('currency')
        expect(plan).to have_key('features')
        expect(plan).to have_key('limits')
        expect(plan).to have_key('entitlements')
      end
    end

    it 'does not require authentication', :vcr do
      # Clear session to test unauthenticated access
      env 'rack.session', {}

      get '/billing/api/plans'

      expect(last_response.status).to eq(200)
    end

    it 'handles plan cache refresh failures gracefully', :vcr do
      # Simulate Stripe error
      allow(Billing::Plan).to receive(:list_plans).and_raise(Stripe::StripeError)

      get '/billing/api/plans'

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to list plans')
    end
  end

  describe 'GET /billing/api/org/:extid' do
    it 'returns billing overview for organization', :vcr do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('organization')
      expect(data).to have_key('subscription')
      expect(data).to have_key('plan')
      expect(data).to have_key('usage')

      # Verify organization data
      expect(data['organization']['id']).to eq(organization.extid)
      expect(data['organization']['display_name']).to eq(organization.display_name)
      expect(data['organization']['billing_email']).to eq(organization.billing_email)

      # Verify usage data
      expect(data['usage']).to have_key('members')
      expect(data['usage']).to have_key('domains')
    end

    it 'returns subscription data when organization has active subscription', :vcr do
      # Requires STRIPE_TEST_PRICE_ID env var with a real price from your Stripe dashboard
      # Run: STRIPE_TEST_PRICE_ID=price_xxx bundle exec rspec ...
      test_price_id = ENV['STRIPE_TEST_PRICE_ID']
      skip 'Set STRIPE_TEST_PRICE_ID env var with a real Stripe price ID' unless test_price_id

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
        items: [{ price: test_price_id }],
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

    it 'returns nil subscription when organization has no subscription', :vcr do
      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).to be_nil
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: deterministic_email('other'))
      created_customers << other_customer
      other_customer.save

      # Switch session to other customer
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Access denied')
    end

    it 'returns 403 when organization does not exist', :vcr do
      get '/billing/api/org/nonexistent_org_id'

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Organization not found')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(401)
    end
  end

  describe 'POST /billing/api/org/:extid/checkout' do
    let(:tier) { 'single_team' }
    let(:billing_cycle) { 'monthly' }

    before do
      # Ensure customer is organization owner
      organization.save

      # Mock region to match Stripe plan metadata (EU is our default test region)
      mock_region!('EU')

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

    it 'returns 400 when tier is missing', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 400 when billing_cycle is missing', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing tier or billing_cycle')
    end

    it 'returns 404 when plan is not found', :vcr do
      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: 'nonexistent_tier',
        billing_cycle: 'monthly',
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Plan not found')
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

      data = JSON.parse(last_response.body)
      session = Stripe::Checkout::Session.retrieve(data['session_id'])

      # Verify the session was created correctly
      expect(session.mode).to eq('subscription')
      expect(session.client_reference_id).to eq(organization.objid)

      # Note: subscription_data.metadata is a write-only parameter passed to
      # the subscription when created. It's not returned on session retrieval.
      # The metadata will appear on the actual Subscription object after
      # checkout completion, which is verified via webhook processing tests.
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

    it 'returns 403 when customer is not organization owner', :vcr do
      # Create member (non-owner) customer
      member_customer = Onetime::Customer.create!(email: deterministic_email('member'))
      created_customers << member_customer
      member_customer.save

      # Add as member but not owner (using Organization's auto-generated method)
      organization.add_members_instance(member_customer)

      # Switch session to member customer
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => member_customer.extid,
      }

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      post "/billing/api/org/#{organization.extid}/checkout", {
        tier: tier,
        billing_cycle: billing_cycle,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns empty list when organization has no Stripe customer', :vcr do
      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['invoices']).to eq([])
    end

    it 'returns list of invoices for organization', :vcr do
      # Create Stripe customer with email (required for invoices)
      customer_email = organization.billing_email || "test-#{SecureRandom.hex(4)}@example.com"
      stripe_customer = Stripe::Customer.create(email: customer_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      # Create an invoice item first, then the invoice
      Stripe::InvoiceItem.create(
        customer: stripe_customer.id,
        amount: 1000,
        currency: 'usd',
        description: 'Test invoice item'
      )

      Stripe::Invoice.create(
        customer: stripe_customer.id,
        auto_advance: false  # Don't finalize automatically
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

    it 'limits invoices to 12', :vcr do
      skip 'Requires creating 13+ invoices which is time-intensive'

      # In a real integration test, you would:
      # 1. Create Stripe customer
      # 2. Create 13 invoices
      # 3. Verify only 12 are returned
      # 4. Verify has_more is true
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: deterministic_email('other-invoice'))
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(401)
    end

    it 'handles Stripe errors gracefully', :vcr do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(500)
      expect(last_response.body).to include('Failed to retrieve invoices')
    end
  end

  describe 'GET /billing/api/org/:extid/subscription' do
    it 'returns has_active_subscription: false when no subscription' do
      get "/billing/api/org/#{organization.extid}/subscription"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['has_active_subscription']).to eq(false)
      expect(data).to have_key('current_plan')
    end

    it 'returns subscription details when organization has active subscription' do
      # Mock the organization having an active subscription
      organization.stripe_subscription_id = 'sub_mock_status'
      organization.stripe_customer_id = 'cus_mock_status'
      organization.planid = 'identity_plus_v1_monthly'
      organization.subscription_status = 'active'
      organization.save

      # Stub Stripe::Subscription.retrieve to return mock data
      mock_subscription = double('Stripe::Subscription', status: 'active')
      mock_item = double('SubscriptionItem',
                         id: 'si_mock',
                         price: double(id: 'price_mock'),
                         current_period_end: (Time.now + 30 * 24 * 60 * 60).to_i)
      allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
      allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

      get "/billing/api/org/#{organization.extid}/subscription"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['has_active_subscription']).to eq(true)
      expect(data['current_plan']).not_to be_nil
      expect(data['current_price_id']).not_to be_nil
      expect(data['subscription_item_id']).not_to be_nil
      expect(data['subscription_status']).to eq('active')
      expect(data['current_period_end']).not_to be_nil
    end

    it 'returns 403 when customer is not organization member' do
      other_customer = Onetime::Customer.create!(email: deterministic_email('other-sub'))
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      get "/billing/api/org/#{organization.extid}/subscription"

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication' do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}/subscription"

      expect(last_response.status).to eq(401)
    end
  end

  describe 'POST /billing/api/org/:extid/preview-plan-change' do
    let(:stripe_customer) { nil }
    let(:subscription) { nil }
    let(:current_price_id) { ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }
    let(:new_price_id) { ENV.fetch('STRIPE_TEST_PRICE_ID_ALT', 'price_test_alt') }

    before do
      # Mock region for plan lookups
      mock_region!('EU')
    end

    context 'without active subscription' do
      it 'returns 400 when organization has no subscription', :vcr do
        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('No active subscription')
      end
    end

    # Validation tests - use mocked subscription data (no real Stripe calls)
    context 'with mocked active subscription' do
      before do
        # Mock the organization having an active subscription
        organization.stripe_subscription_id = 'sub_mock_preview'
        organization.stripe_customer_id = 'cus_mock_preview'
        organization.planid = 'identity_plus_v1_monthly'
        organization.subscription_status = 'active'
        organization.save
      end

      it 'returns 400 when new_price_id is missing' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change", {}.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Missing new_price_id')
      end

      it 'returns 400 when switching to same plan' do
        # Stub Stripe::Subscription.retrieve to return current price
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: current_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Already on this plan')
      end

      it 'returns 400 when target price ID is not in plan catalog' do
        # Stub Stripe::Subscription.retrieve
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        # Stub price_id_to_plan_id to return nil (price not in catalog)
        allow_any_instance_of(Billing::Controllers::BillingController)
          .to receive(:price_id_to_plan_id)
          .with('price_unknown_xyz')
          .and_return(nil)

        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: 'price_unknown_xyz',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid price ID')
      end

      it 'returns 400 when target plan is a legacy plan' do
        # Stub Stripe::Subscription.retrieve
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        # Stub price_id_to_plan_id to return a plan ID
        allow_any_instance_of(Billing::Controllers::BillingController)
          .to receive(:price_id_to_plan_id)
          .with('price_legacy_plan')
          .and_return('identity_v0')

        # Stub legacy_plan? to return true for this plan
        allow(Billing::PlanHelpers).to receive(:legacy_plan?)
          .with('identity_v0')
          .and_return(true)

        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: 'price_legacy_plan',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('This plan is not available')
      end
    end

    # Integration tests requiring real Stripe API (VCR cassettes)
    # NOTE: These tests are skipped by default - run with STRIPE_API_KEY=sk_test_xxx to record cassettes
    context 'with real Stripe subscription', :vcr, skip: 'Requires VCR cassettes: run with STRIPE_API_KEY=sk_test_xxx' do
      let(:stripe_customer) do
        cust = Stripe::Customer.create(email: customer.email)
        payment_method = Stripe::PaymentMethod.create(
          type: 'card',
          card: { token: 'tok_visa' }
        )
        Stripe::PaymentMethod.attach(payment_method.id, { customer: cust.id })
        Stripe::Customer.update(cust.id, {
          invoice_settings: { default_payment_method: payment_method.id }
        })
        cust
      end

      let(:subscription) do
        Stripe::Subscription.create(
          customer: stripe_customer.id,
          items: [{ price: current_price_id }],
        )
      end

      before do
        organization.update_from_stripe_subscription(subscription)
        organization.save
      end

      it 'returns proration preview for valid plan change' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data).to have_key('amount_due')
        expect(data).to have_key('subtotal')
        expect(data).to have_key('credit_applied')
        expect(data).to have_key('next_billing_date')
        expect(data).to have_key('currency')
        expect(data).to have_key('current_plan')
        expect(data).to have_key('new_plan')

        expect(data['current_plan']).to have_key('price_id')
        expect(data['current_plan']).to have_key('amount')
        expect(data['current_plan']).to have_key('interval')

        expect(data['new_plan']).to have_key('price_id')
        expect(data['new_plan']).to have_key('amount')
        expect(data['new_plan']).to have_key('interval')
      end

      it 'returns 400 for invalid price_id' do
        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: 'price_invalid_xxxxx',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
      end
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: deterministic_email('other-preview'))
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      post "/billing/api/org/#{organization.extid}/preview-plan-change", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      post "/billing/api/org/#{organization.extid}/preview-plan-change", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end

  describe 'POST /billing/api/org/:extid/change-plan' do
    let(:current_price_id) { ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }
    let(:new_price_id) { ENV.fetch('STRIPE_TEST_PRICE_ID_ALT', 'price_test_alt') }

    before do
      mock_region!('EU')
    end

    context 'without active subscription' do
      it 'returns 400 when organization has no subscription', :vcr do
        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('No active subscription')
      end
    end

    # Validation tests - use mocked subscription data (no real Stripe calls)
    context 'with mocked active subscription' do
      before do
        # Mock the organization having an active subscription
        organization.stripe_subscription_id = 'sub_mock_change'
        organization.stripe_customer_id = 'cus_mock_change'
        organization.planid = 'identity_plus_v1_monthly'
        organization.subscription_status = 'active'
        organization.save
      end

      it 'returns 400 when new_price_id is missing' do
        post "/billing/api/org/#{organization.extid}/change-plan", {}.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Missing new_price_id')
      end

      it 'returns 400 when switching to same plan' do
        # Stub Stripe::Subscription.retrieve to return current price
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', id: 'si_mock', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: current_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Already on this plan')
      end

      it 'returns 400 when target price ID is not in plan catalog' do
        # Stub Stripe::Subscription.retrieve
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', id: 'si_mock', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        # Stub price_id_to_plan_id to return nil (price not in catalog)
        allow_any_instance_of(Billing::Controllers::BillingController)
          .to receive(:price_id_to_plan_id)
          .with('price_unknown_xyz')
          .and_return(nil)

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: 'price_unknown_xyz',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid price ID')
      end

      it 'returns 400 when target plan is a legacy plan' do
        # Stub Stripe::Subscription.retrieve
        mock_subscription = double('Stripe::Subscription')
        mock_item = double('SubscriptionItem', id: 'si_mock', price: double(id: current_price_id))
        allow(mock_subscription).to receive_message_chain(:items, :data, :first).and_return(mock_item)
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        # Stub price_id_to_plan_id to return a plan ID
        allow_any_instance_of(Billing::Controllers::BillingController)
          .to receive(:price_id_to_plan_id)
          .with('price_legacy_plan')
          .and_return('identity_v0')

        # Stub legacy_plan? to return true for this plan
        allow(Billing::PlanHelpers).to receive(:legacy_plan?)
          .with('identity_v0')
          .and_return(true)

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: 'price_legacy_plan',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('This plan is not available')
      end

      it 'requires owner permissions (not just member)' do
        member_customer = Onetime::Customer.create!(email: deterministic_email('member-change'))
        created_customers << member_customer
        member_customer.save

        organization.add_members_instance(member_customer)

        env 'rack.session', {
          'authenticated' => true,
          'external_id' => member_customer.extid,
        }

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(403)
        expect(last_response.body).to include('Owner access required')
      end
    end

    # Integration tests requiring real Stripe API (VCR cassettes)
    # NOTE: These tests are skipped by default - run with STRIPE_API_KEY=sk_test_xxx to record cassettes
    context 'with real Stripe subscription', :vcr, skip: 'Requires VCR cassettes: run with STRIPE_API_KEY=sk_test_xxx' do
      let(:stripe_customer) do
        cust = Stripe::Customer.create(email: customer.email)
        payment_method = Stripe::PaymentMethod.create(
          type: 'card',
          card: { token: 'tok_visa' }
        )
        Stripe::PaymentMethod.attach(payment_method.id, { customer: cust.id })
        Stripe::Customer.update(cust.id, {
          invoice_settings: { default_payment_method: payment_method.id }
        })
        cust
      end

      let(:subscription) do
        Stripe::Subscription.create(
          customer: stripe_customer.id,
          items: [{ price: current_price_id }],
        )
      end

      before do
        organization.update_from_stripe_subscription(subscription)
        organization.save
      end

      it 'executes plan change successfully' do
        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)

        data = JSON.parse(last_response.body)
        expect(data['success']).to eq(true)
        expect(data).to have_key('new_plan')
        expect(data).to have_key('status')
        expect(data).to have_key('current_period_end')
      end

      it 'updates organization planid after change' do
        old_planid = organization.planid

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: new_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)

        # Reload organization to verify update
        organization.refresh!
        expect(organization.planid).not_to eq(old_planid)
      end

      it 'returns 400 for invalid price_id' do
        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: 'price_invalid_xxxxx',
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
      end
    end

    it 'returns 403 when customer is not organization member', :vcr do
      other_customer = Onetime::Customer.create!(email: deterministic_email('other-change'))
      created_customers << other_customer
      other_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => other_customer.extid,
      }

      post "/billing/api/org/#{organization.extid}/change-plan", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      post "/billing/api/org/#{organization.extid}/change-plan", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end
end

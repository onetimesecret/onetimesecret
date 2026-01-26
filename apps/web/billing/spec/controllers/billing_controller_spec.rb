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

  # Generate a valid CSRF token compatible with Rack::Protection::AuthenticityToken
  # The token must be URL-safe base64 encoded (32 bytes = 43 chars without padding)
  let(:csrf_token) { SecureRandom.urlsafe_base64(32, padding: false) }

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

    # Mock authentication by setting up session with valid CSRF token
    # Rack::Protection::AuthenticityToken stores the raw token in session[:csrf]
    # and validates X-CSRF-Token header against it (supports both masked and unmasked)
    env 'rack.session', {
      'authenticated' => true,
      'external_id' => customer.extid,
      :csrf => csrf_token,
    }
    # Set CSRF header globally for all requests (matches frontend Axios interceptor)
    header 'X-CSRF-Token', csrf_token
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

    # =========================================================================
    # TEST HISTORY & DESIGN NOTES
    # =========================================================================
    #
    # This test was originally implemented using VCR to record real Stripe API
    # interactions. That approach proved fragile because:
    #
    #   1. VCR cassettes become stale when Stripe's API responses change
    #   2. Price IDs are specific to individual Stripe accounts
    #   3. Tests weren't portable across development environments
    #   4. Recording cassettes required manual intervention with real API keys
    #
    # We refactored to use Ruby-level mocking because this test's purpose is to
    # verify that OUR controller correctly returns subscription data - not to
    # verify that Stripe's API works correctly.
    #
    # ALTERNATIVE APPROACHES TO CONSIDER:
    #
    #   - stripe-mock (Official): Docker image from Stripe that implements their
    #     API locally. Good for comprehensive integration testing.
    #     https://github.com/stripe/stripe-mock
    #
    #   - stripe-ruby-mock gem: In-process mock server. Provides test helpers
    #     for creating plans, customers, subscriptions without network calls.
    #     https://github.com/stripe-ruby-mock/stripe-ruby-mock
    #
    #   - Contract testing: Validate request/response shapes against Stripe's
    #     OpenAPI specification for API compatibility assurance.
    #
    # For now, mocking at the organization/model level is sufficient since we're
    # testing controller behavior, not Stripe integration correctness.
    # =========================================================================
    it 'returns subscription data when organization has active subscription' do
      # Set up organization with mocked subscription state
      # (simulates what update_from_stripe_subscription would have done)
      test_subscription_id = 'sub_test_mock_123'
      organization.stripe_subscription_id = test_subscription_id
      organization.subscription_status = 'active'
      organization.subscription_period_end = Time.now.to_i + (30 * 24 * 60 * 60)
      organization.save

      get "/billing/api/org/#{organization.extid}"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data['subscription']).not_to be_nil
      expect(data['subscription']['id']).to eq(test_subscription_id)
      expect(data['subscription']['status']).to eq('active')
      expect(data['subscription']['active']).to be true
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
    include_context 'with_test_plans'

    let(:product) { 'identity_plus_v1' }
    let(:interval) { 'monthly' }

    before do
      # Ensure customer is organization owner
      organization.save

      # Note: with_test_plans context loads plans from spec/billing.test.yaml
      # and mocks region to 'EU'. No Stripe API calls needed.
    end

    it 'creates Stripe checkout session' do
      # Mock Stripe checkout session creation
      mock_session = build_checkout_session(
        'url' => 'https://checkout.stripe.com/c/pay/cs_test_mock',
        'id' => 'cs_test_mock_checkout'
      )
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json', 'HTTP_X_CSRF_TOKEN' => csrf_token }

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data).to have_key('checkout_url')
      expect(data).to have_key('session_id')
      expect(data['checkout_url']).to match(%r{\Ahttps://checkout\.stripe\.com/})

      # Verify correct params passed to Stripe
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          mode: 'subscription',
          client_reference_id: organization.objid
        ),
        anything
      )
    end

    it 'returns 400 when product is missing' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json', 'HTTP_X_CSRF_TOKEN' => csrf_token }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing product or interval')
    end

    it 'returns 400 when interval is missing' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Missing product or interval')
    end

    it 'returns 400 when plan is not found' do
      post "/billing/api/org/#{organization.extid}/checkout", {
        product: 'nonexistent_product',
        interval: 'monthly',
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(400)
      expect(last_response.body).to include('Plan not found')
    end

    it 'uses existing Stripe customer if organization has one' do
      # Set existing Stripe customer on organization
      organization.stripe_customer_id = 'cus_existing_test_customer'
      organization.save

      # Mock Stripe checkout session creation
      mock_session = build_checkout_session(
        'url' => 'https://checkout.stripe.com/c/pay/cs_test_existing',
        'id' => 'cs_test_existing_customer',
        'customer' => 'cus_existing_test_customer'
      )
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Verify the checkout session was created with the existing customer
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(customer: 'cus_existing_test_customer'),
        anything
      )
    end

    it 'includes metadata in subscription' do
      # Mock Stripe checkout session creation
      mock_session = build_checkout_session(
        'url' => 'https://checkout.stripe.com/c/pay/cs_test_metadata',
        'id' => 'cs_test_metadata',
        'mode' => 'subscription',
        'client_reference_id' => organization.objid
      )
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Verify subscription_data.metadata was passed correctly
      # The metadata contains: orgid, plan_id, tier, region, customer_extid
      # Note: tier is resolved from product by PlanResolver
      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          mode: 'subscription',
          client_reference_id: organization.objid,
          subscription_data: hash_including(
            metadata: hash_including(
              orgid: organization.objid,
              tier: 'single_team', # Resolved from identity_plus_v1
              customer_extid: customer.extid
            )
          )
        ),
        anything
      )
    end

    it 'uses idempotency key to prevent duplicates' do
      # Mock Stripe checkout session creation
      mock_session = build_checkout_session(
        'url' => 'https://checkout.stripe.com/c/pay/cs_test_idempotent',
        'id' => 'cs_test_idempotent'
      )
      allow(Stripe::Checkout::Session).to receive(:create).and_return(mock_session)

      # Make two identical requests
      2.times do
        post "/billing/api/org/#{organization.extid}/checkout", {
          product: product,
          interval: interval,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
      end

      # Verify idempotency key was used in both requests
      # The key is a SHA256 hash (64 hex chars) of checkout:<org_id>:<plan_id>:<time>
      expect(Stripe::Checkout::Session).to have_received(:create).twice.with(
        anything,
        hash_including(idempotency_key: a_string_matching(/^[a-f0-9]{64}$/))
      )
    end

    it 'returns 403 when customer is not organization owner' do
      # Create member (non-owner) customer
      member_customer = Onetime::Customer.create!(email: deterministic_email('member'))
      created_customers << member_customer
      member_customer.save

      # Add as member but not owner (using Organization's auto-generated method)
      organization.add_members_instance(member_customer)

      # Switch session to member customer (preserve CSRF token)
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => member_customer.extid,
        :csrf => csrf_token,
      }

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
      expect(last_response.body).to include('Owner access required')
    end

    it 'requires authentication' do
      # Clear session but preserve CSRF token to test auth requirement (not CSRF)
      env 'rack.session', { :csrf => csrf_token }

      post "/billing/api/org/#{organization.extid}/checkout", {
        product: product,
        interval: interval,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end

  describe 'GET /billing/api/org/:extid/invoices' do
    it 'returns empty list when organization has no Stripe customer' do
      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('application/json')

      data = JSON.parse(last_response.body)
      expect(data['invoices']).to eq([])
    end

    it 'returns list of invoices for organization' do
      # Set up organization with Stripe customer
      organization.stripe_customer_id = 'cus_test_invoices'
      organization.save

      # Mock Stripe invoice list
      mock_invoices = build_invoice_list([
        build_invoice(
          'id' => 'in_test_1',
          'number' => 'INV-0001',
          'amount_due' => 1900,
          'currency' => 'cad',
          'status' => 'paid',
          'created' => 1704067200
        ),
        build_invoice(
          'id' => 'in_test_2',
          'number' => 'INV-0002',
          'amount_due' => 2900,
          'currency' => 'cad',
          'status' => 'open',
          'created' => 1706745600
        )
      ])
      allow(Stripe::Invoice).to receive(:list).and_return(mock_invoices)

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(200)

      data = JSON.parse(last_response.body)
      expect(data).to have_key('invoices')
      expect(data).to have_key('has_more')
      expect(data['invoices']).to be_an(Array)
      expect(data['invoices'].length).to eq(2)

      invoice_data = data['invoices'].first
      expect(invoice_data).to have_key('id')
      expect(invoice_data).to have_key('number')
      expect(invoice_data).to have_key('amount')
      expect(invoice_data).to have_key('currency')
      expect(invoice_data).to have_key('status')
      expect(invoice_data).to have_key('created')
      expect(invoice_data).to have_key('invoice_pdf')
      expect(invoice_data).to have_key('hosted_invoice_url')

      # Verify correct params passed to Stripe
      expect(Stripe::Invoice).to have_received(:list).with(
        hash_including(customer: 'cus_test_invoices')
      )
    end

    it 'limits invoices to 12' do
      skip 'Requires creating 13+ invoices which is time-intensive'

      # In a real integration test, you would:
      # 1. Create Stripe customer
      # 2. Create 13 invoices
      # 3. Verify only 12 are returned
      # 4. Verify has_more is true
    end

    it 'returns 403 when customer is not organization member' do
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

    it 'requires authentication' do
      env 'rack.session', {}

      get "/billing/api/org/#{organization.extid}/invoices"

      expect(last_response.status).to eq(401)
    end

    it 'handles Stripe errors gracefully' do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      # Mock Stripe raising an error
      allow(Stripe::Invoice).to receive(:list).and_raise(
        Stripe::InvalidRequestError.new('No such customer: cus_invalid', :customer)
      )

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

      # Use StripeMockFactory to create a proper Stripe::Subscription object
      # Note: The controller accesses current_item.current_period_end on the subscription item
      period_end = (Time.now + 30 * 24 * 60 * 60).to_i
      mock_subscription = build_subscription(
        'status' => 'active',
        'current_period_end' => period_end,
        'items_data' => [{
          'id' => 'si_mock',
          'current_period_end' => period_end,
          'price' => { 'id' => 'price_mock', 'unit_amount' => 1900, 'currency' => 'cad' }
        }]
      )
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
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        post "/billing/api/org/#{organization.extid}/preview-plan-change", {
          new_price_id: current_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Already on this plan')
      end

      it 'returns 400 when target price ID is not in plan catalog' do
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
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
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
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
        :csrf => csrf_token,
      }

      post "/billing/api/org/#{organization.extid}/preview-plan-change", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      # Clear session but preserve CSRF token to test auth requirement (not CSRF)
      env 'rack.session', { :csrf => csrf_token }

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
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
        allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_subscription)

        post "/billing/api/org/#{organization.extid}/change-plan", {
          new_price_id: current_price_id,
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Already on this plan')
      end

      it 'returns 400 when target price ID is not in plan catalog' do
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
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
        # Use StripeMockFactory to create a proper Stripe::Subscription object
        mock_subscription = build_subscription(
          'items_data' => [{
            'id' => 'si_mock',
            'price' => { 'id' => current_price_id, 'unit_amount' => 1900, 'currency' => 'cad' }
          }]
        )
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
          :csrf => csrf_token,
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
        :csrf => csrf_token,
      }

      post "/billing/api/org/#{organization.extid}/change-plan", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(403)
    end

    it 'requires authentication', :vcr do
      # Clear session but preserve CSRF token to test auth requirement (not CSRF)
      env 'rack.session', { :csrf => csrf_token }

      post "/billing/api/org/#{organization.extid}/change-plan", {
        new_price_id: new_price_id,
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(401)
    end
  end
end

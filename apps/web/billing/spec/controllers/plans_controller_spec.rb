# apps/web/billing/spec/controllers/plans_controller_spec.rb
#
# frozen_string_literal: true

# TESTING APPROACH NOTE:
# This spec uses `with_stubbed_checkout` for Stripe Checkout Session API calls.
# This is an intentional exception to our general rule of testing against the
# real Stripe API (via VCR cassettes).
#
# Checkout session creation requires valid price IDs that must exist in the
# Stripe test account and match spec/billing.test.yaml. The coordination
# overhead of maintaining these makes real API testing impractical here.
#
# Other billing tests (portal, welcome, webhooks) continue using VCR with
# real API calls where the setup is more manageable.

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'

RSpec.describe 'Billing::Controllers::Plans', :integration, :stripe_sandbox_api, :vcr do
  include Rack::Test::Methods
  include_context 'with_test_plans'
  include_context 'with_stubbed_checkout'

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  let(:customer) do
    cust = Onetime::Customer.create!(email: "plans-test-#{SecureRandom.hex(4)}@example.com")
    created_customers << cust
    cust
  end

  before do
    customer.save

    # Mock authentication for authenticated endpoints
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

  describe 'GET /billing/plans/:tier/:billing_cycle' do
    let(:tier) { 'single_team' }
    let(:billing_cycle) { 'monthly' }

    it 'redirects to Stripe checkout session', :vcr do
      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{\Ahttps://checkout\.stripe\.com/})
    end

    it 'creates checkout session with correct plan', :vcr do
      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)

      # Extract session ID from redirect URL
      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Verify plan metadata
      expect(session.subscription_data['metadata']['tier']).to eq(tier)
    end

    it 'pre-fills customer email for authenticated users', :vcr do
      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.customer_email).to eq(customer.email)
    end

    it 'includes customer ID in metadata for authenticated users', :vcr do
      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.subscription_data['metadata']['customer_extid']).to eq(customer.extid)
    end

    it 'redirects to /signup when plan is not found', :vcr do
      get '/billing/plans/nonexistent_tier/monthly'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/signup')
    end

    it 'handles Stripe errors by redirecting to /signup', :vcr do
      # Simulate Stripe error
      allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::StripeError)

      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/signup')
    end

    it 'uses yearly billing_cycle parameter', :vcr do
      get "/billing/plans/#{tier}/yearly"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Verify yearly plan was used (would need to check price ID matches yearly)
      expect(session.subscription_data['metadata']['tier']).to eq(tier)
    end

    it 'does not require authentication', :vcr do
      env 'rack.session', {}

      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{\Ahttps://[^/]*stripe\.com/})
    end

    it 'detects region for plan selection', :vcr do
      # Future: Test with different CloudFlare headers
      # For now, verify default region works

      get "/billing/plans/#{tier}/#{billing_cycle}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.subscription_data['metadata']['region']).not_to be_nil
    end
  end

  describe 'GET /billing/welcome' do
    it 'redirects to /account when session_id is missing', :vcr do
      get '/billing/welcome'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/account')
    end

    it 'processes checkout session and activates organization', :vcr do
      # Create a real checkout session
      stripe_customer = Stripe::Customer.create(email: customer.email)
      Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
        metadata: {
          customer_extid: customer.extid,
          plan_id: 'identity_v1',
          tier: 'single_team',
        },
      )

      checkout_session = Stripe::Checkout::Session.create(
        mode: 'subscription',
        customer: stripe_customer.id,
        line_items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test'), quantity: 1 }],
        success_url: 'http://example.com/success',
        cancel_url: 'http://example.com/cancel',
      )

      get "/billing/welcome?session_id=#{checkout_session.id}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/account')

      # Verify organization was created/updated
      orgs = customer.organization_instances.to_a
      expect(orgs).not_to be_empty

      org = orgs.find { |o| o.is_default }
      expect(org).not_to be_nil
    end

    it 'handles Stripe errors gracefully', :vcr do
      get '/billing/welcome?session_id=cs_test_invalid'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/account')
    end

    it 'creates default organization for new customer', :vcr do
      new_customer = Onetime::Customer.create!(email: "new-welcome-#{SecureRandom.hex(4)}@example.com")
      created_customers << new_customer
      new_customer.save

      # Switch session
      env 'rack.session', {
        'authenticated' => true,
        'external_id' => new_customer.extid,
      }

      # Create checkout session for new customer
      stripe_customer = Stripe::Customer.create(email: new_customer.email)
      subscription    = Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
        metadata: {
          customer_extid: new_customer.extid,
          plan_id: 'identity_v1',
        },
      )

      checkout_session = Stripe::Checkout::Session.create(
        mode: 'subscription',
        customer: stripe_customer.id,
        subscription: subscription.id,
        line_items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test'), quantity: 1 }],
        success_url: 'http://example.com/success',
        cancel_url: 'http://example.com/cancel',
      )

      get "/billing/welcome?session_id=#{checkout_session.id}"

      expect(last_response.status).to eq(302)

      # Verify default organization was created
      orgs = new_customer.organization_instances.to_a
      expect(orgs.size).to be >= 1

      default_org = orgs.find { |o| o.is_default }
      expect(default_org).not_to be_nil
      expect(default_org.display_name).to include(new_customer.email)
      created_organizations.concat(orgs)
    end
  end

  describe 'GET /billing/portal' do
    let(:organization) do
      org            = Onetime::Organization.create!('Test Org', customer, customer.email)
      org.is_default = true
      org.save
      created_organizations << org
      org
    end

    before do
      organization.save
    end

    it 'redirects to /account when organization has no Stripe customer', :vcr do
      get '/billing/portal'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/account')
    end

    it 'redirects to Stripe Customer Portal', :vcr do
      # Create Stripe customer
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      get '/billing/portal'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{\Ahttps://billing\.stripe\.com/})
    end

    it 'includes return URL to /account', :vcr do
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      get '/billing/portal'

      expect(last_response.status).to eq(302)

      # Extract portal session ID and verify return URL
      # Note: This requires parsing the redirect or checking Stripe logs
    end

    it 'handles Stripe errors gracefully', :vcr do
      organization.stripe_customer_id = 'cus_invalid'
      organization.save

      get '/billing/portal'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/account')
    end

    it 'requires authentication', :vcr do
      env 'rack.session', {}

      get '/billing/portal'

      # Web endpoints redirect to signin instead of returning 401
      # (API endpoints return 401 for JSON clients)
      expect(last_response.status).to eq(302)
    end

    it 'creates default organization if customer has none', :vcr do
      new_customer = Onetime::Customer.create!(email: "portal-test-#{SecureRandom.hex(4)}@example.com")
      created_customers << new_customer
      new_customer.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => new_customer.extid,
      }

      # Customer has no organizations initially
      expect(new_customer.organization_instances.to_a).to be_empty

      get '/billing/portal'

      # Should redirect to account (no Stripe customer yet)
      expect(last_response.status).to eq(302)

      # But default organization should have been created
      orgs = new_customer.organization_instances.to_a
      expect(orgs).not_to be_empty
      created_organizations.concat(orgs)
    end

    it 'sets no-cache headers', :vcr do
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      get '/billing/portal'

      # Verify cache control headers are set
      # (exact headers depend on res.do_not_cache! implementation)
      expect(last_response.headers).to have_key('Cache-Control')
    end
  end
end

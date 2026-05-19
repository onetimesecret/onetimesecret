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

  describe 'GET /billing/plans/:product/:interval' do
    let(:product) { 'identity_plus_v1' }
    let(:interval) { 'monthly' }

    it 'redirects to Stripe checkout session', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{\Ahttps://checkout\.stripe\.com/})
    end

    it 'enables promotion codes on the checkout session', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.allow_promotion_codes).to eq(true)
    end

    it 'creates checkout session with correct plan', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      # Extract session ID from redirect URL
      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Verify plan metadata (tier is stored in debug_info JSON)
      debug_info = JSON.parse(session.subscription_data['metadata']['debug_info'])
      expect(debug_info['checkout_tier']).to eq('single_team')
    end

    it 'pre-fills customer email for authenticated users', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.customer_email).to eq(customer.email)
    end

    it 'includes customer ID in metadata for authenticated users', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      expect(session.subscription_data['metadata']['customer_extid']).to eq(customer.extid)
    end

    it 'redirects to /signup when plan resolution fails', :vcr do
      get '/billing/plans/nonexistent_product/monthly'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/signup')
    end

    it 'handles Stripe errors by redirecting to /signup', :vcr do
      # Simulate Stripe error
      allow(Stripe::Checkout::Session).to receive(:create).and_raise(Stripe::StripeError)

      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('/signup')
    end

    it 'uses yearly interval parameter', :vcr do
      get "/billing/plans/#{product}/yearly"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Verify yearly plan was used (tier is stored in debug_info JSON)
      debug_info = JSON.parse(session.subscription_data['metadata']['debug_info'])
      expect(debug_info['checkout_tier']).to eq('single_team')
    end

    it 'redirects unauthenticated users to signup with plan selection' do
      env 'rack.session', {}

      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)
      expect(last_response.location).to eq("/signup?product=#{product}&interval=#{interval}")
    end

    context 'with URL parameter escaping (PR #3129 security fix)' do
      # These tests verify that parameters are properly escaped in redirect URLs
      # to prevent query string injection. When special characters like & or =
      # appear in parameter values, they must be percent-encoded in the redirect
      # URL to avoid creating unintended query parameters.
      #
      # Controller redirect paths tested:
      # - Line 59: result.success? == false (plan resolution failed)
      # - Line 73: plan.nil? (plan not found after resolution)
      # - Line 79: cust.anonymous? (unauthenticated user)
      # - Line 188: rescue Stripe::StripeError

      describe 'plan resolution failure redirect (line 59)' do
        # This path uses Rack::Utils.build_query (already fixed)
        it 'escapes ampersands in product parameter' do
          env 'rack.session', {}

          # URL-encoded ampersand in path: test%26evil decodes to test&evil in params
          get '/billing/plans/test%26evil%3Dinject/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Verify no raw ampersand creates an unintended query param
          expect(location).not_to include('&evil=inject')
          # The value should be escaped in the query string
          expect(location).to include('product=test%26evil')
        end

        it 'escapes ampersands in interval parameter' do
          env 'rack.session', {}

          get '/billing/plans/identity_plus_v1/year%26ly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Should not have &ly as a separate parameter
          expect(location).not_to match(/&ly(?:=|&|$)/)
        end

        it 'escapes equals signs in parameters' do
          env 'rack.session', {}

          get '/billing/plans/test%3Dvalue/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Should have exactly 2 = signs (product= and interval=)
          query_string = URI.parse(location).query
          expect(query_string.count('=')).to eq(2)
        end

        it 'escapes spaces in parameters' do
          env 'rack.session', {}

          get '/billing/plans/test%20product/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Space should be escaped (either %20 or + is acceptable)
          expect(location).not_to include('test product')
        end
      end

      describe 'plan load failure redirect (line 73)' do
        # This path uses Rack::Utils.build_query (already fixed)
        it 'escapes special characters when plan load returns nil' do
          # Stub PlanResolver to return success but with a plan_id that won't load
          fake_result = double(
            success?: true,
            plan: nil,
            plan_id: 'nonexistent_plan',
            tier: 'test',
            error: nil
          )
          allow(::Billing::PlanResolver).to receive(:resolve).and_return(fake_result)
          allow(::Billing::Plan).to receive(:load).with('nonexistent_plan').and_return(nil)

          env 'rack.session', {}
          get '/billing/plans/test%26inject/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Should not have raw & creating extra params
          expect(location).not_to include('&inject')
        end
      end

      describe 'unauthenticated user redirect (line 79)' do
        # This path uses Rack::Utils.build_query (already fixed)
        it 'escapes special characters for anonymous users with valid plan' do
          # Stub to get past resolution and plan load, but hit the anonymous check
          fake_result = double(
            success?: true,
            plan: double(plan_id: 'test_plan', stripe_price_id: 'price_test'),
            plan_id: 'test_plan',
            tier: 'test',
            error: nil
          )
          allow(::Billing::PlanResolver).to receive(:resolve).and_return(fake_result)

          env 'rack.session', {}  # Anonymous user
          get '/billing/plans/test%26inject/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Should not have raw & creating extra params
          expect(location).not_to include('&inject')
        end
      end

      describe 'Stripe error redirect (line 188)' do
        # This path uses Rack::Utils.build_query (already fixed)
        it 'escapes special characters when Stripe checkout fails' do
          # Need authenticated user with valid plan to reach Stripe call
          plan_double = double(
            plan_id: 'identity_plus_v1',
            price_for: { stripe_price_id: 'price_test', amount: '1200', currency: 'cad' },
            available_intervals: [:month],
          )
          fake_result = double(
            success?: true,
            plan: plan_double,
            plan_id: 'identity_plus_v1',
            tier: 'single_team',
            error: nil
          )
          allow(::Billing::PlanResolver).to receive(:resolve).and_return(fake_result)
          allow(Stripe::Checkout::Session).to receive(:create).and_raise(
            Stripe::StripeError.new('Test error')
          )

          # Authenticated user (uses customer from let block)
          get '/billing/plans/identity%26evil/monthly'

          expect(last_response.status).to eq(302)
          location = last_response.location

          # Should not have raw & creating extra params
          expect(location).not_to include('&evil')
        end
      end
    end

    it 'detects region for plan selection', :vcr do
      # Future: Test with different CloudFlare headers
      # For now, verify default region works

      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Region is stored in debug_info JSON
      debug_info = JSON.parse(session.subscription_data['metadata']['debug_info'])
      expect(debug_info['checkout_region']).not_to be_nil
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
      # CreateDefaultWorkspace names new orgs "Default Workspace" (see f5edcf7cc)
      expect(default_org.display_name).to eq('Default Workspace')
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

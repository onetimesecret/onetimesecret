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

    # Payment-method-configuration pin (issue #4013): deployment policy via
    # STRIPE_PAYMENT_METHOD_CONFIGURATION / billing.yaml, applied by this
    # legacy path with the same guarded assignment as build_session_params.
    # Asserted against the create params (not the retrieved session) because
    # the stubbed session object does not echo this key back.
    context 'payment method configuration (issue #4013)' do
      it 'pins the checkout session to the configured pmc id' do
        allow(Onetime.billing_config)
          .to receive(:payment_method_configuration).and_return('pmc_test123')

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(payment_method_configuration: 'pmc_test123'),
          anything,
        )
      end

      it 'omits the key entirely when the config is unset' do
        allow(Onetime.billing_config)
          .to receive(:payment_method_configuration).and_return(nil)

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
          expect(params).not_to have_key(:payment_method_configuration)
        end
      end

      # ADR-033: boot only format-checks the configured pmc id; existence in
      # the connected Stripe account is discovered here, at first use. That
      # discovery must produce a pointed operator log WITHOUT changing the
      # user-facing redirect, and must not fire for any other Stripe error.
      context 'resource_missing discrimination' do
        let(:billing_logger_spy) { spy('BillingLogger') }

        before do
          allow(Onetime).to receive(:get_logger).and_call_original
          allow(Onetime).to receive(:get_logger).with('Billing').and_return(billing_logger_spy)
          allow(Onetime.billing_config)
            .to receive(:payment_method_configuration).and_return('pmc_test123')
        end

        def stub_resource_missing(message, param)
          allow(Stripe::Checkout::Session).to receive(:create).and_raise(
            Stripe::InvalidRequestError.new(
              message, param, http_status: 400, code: 'resource_missing'
            ),
          )
        end

        it 'logs a pointed operator error and keeps the generic /signup redirect' do
          stub_resource_missing(
            "No such payment method configuration: 'pmc_test123'",
            'payment_method_configuration',
          )

          get "/billing/plans/#{product}/#{interval}"

          # User-facing behavior unchanged: same generic redirect as any
          # other Stripe error.
          expect(last_response.status).to eq(302)
          expect(last_response.location).to eq("/signup?product=#{product}&interval=#{interval}")

          expect(billing_logger_spy).to have_received(:error).with(
            a_string_including('"pmc_test123"')
              .and(a_string_including('does not exist in the connected Stripe account'))
              .and(a_string_including('live/test mode mismatch'))
              .and(a_string_including('STRIPE_PAYMENT_METHOD_CONFIGURATION')),
          )
          # The pre-existing generic error log still fires afterwards.
          expect(billing_logger_spy).to have_received(:error).with(
            'Stripe checkout session creation failed', hash_including(:exception)
          )
        end

        it 'does not emit the pmc log line for resource_missing on a different param' do
          stub_resource_missing("No such customer: 'cus_nope'", 'customer')

          get "/billing/plans/#{product}/#{interval}"

          expect(last_response.status).to eq(302)
          expect(last_response.location).to eq("/signup?product=#{product}&interval=#{interval}")

          expect(billing_logger_spy).not_to have_received(:error).with(
            a_string_including('does not exist in the connected Stripe account'),
          )
          expect(billing_logger_spy).to have_received(:error).with(
            'Stripe checkout session creation failed', hash_including(:exception)
          )
        end
      end
    end

    it 'creates checkout session with correct plan', :vcr do
      get "/billing/plans/#{product}/#{interval}"

      expect(last_response.status).to eq(302)

      # Extract session ID from redirect URL
      session_id = last_response.location.match(%r{/pay/([^?]+)})[1]
      session    = Stripe::Checkout::Session.retrieve(session_id)

      # Verify plan metadata (tier is stored in debug_info JSON)
      debug_info = JSON.parse(session.subscription_data['metadata']['debug_info'])
      expect(debug_info['checkout_tier']).to eq('single_account')
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
      expect(debug_info['checkout_tier']).to eq('single_account')
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
            price_for: { 'stripe_price_id' => 'price_test', 'amount' => '1200', 'currency' => 'cad' },
            available_intervals: ['month'],
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

    # =========================================================================
    # Idempotency key coverage (Copilot request)
    # =========================================================================
    #
    # Mirrors the two assertions in billing_controller_spec: the redirect path
    # must send a UUID-format idempotency key and a DISTINCT key per attempt so
    # rapid retries never receive a cached (possibly already-completed) session.
    it 'sends a UUID-format idempotency key that differs per checkout attempt' do
      captured_keys = []
      allow(Stripe::Checkout::Session).to receive(:create) do |_params, opts|
        captured_keys << opts&.dig(:idempotency_key)
        build_checkout_session(
          'url' => 'https://checkout.stripe.com/c/pay/cs_test_idem',
          'id' => 'cs_test_idem'
        )
      end

      2.times do
        get "/billing/plans/#{product}/#{interval}"
        expect(last_response.status).to eq(302)
      end

      uuid_format = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
      expect(captured_keys.length).to eq(2)
      expect(captured_keys).to all(match(uuid_format))
      expect(captured_keys.uniq.length).to eq(2)
    end

    # =========================================================================
    # Duplicate-subscription guard on the redirect path (issue #2605)
    # =========================================================================
    #
    # The same creation-time guard as the API path, expressed as a redirect
    # (this path serves HTML, not JSON). Only relevant for authenticated
    # returning subscribers whose default org already owns a subscription.
    context 'duplicate-subscription guard (issue #2605)' do
      let(:default_org) do
        org            = Onetime::Organization.create!('Guard Org', customer, customer.email)
        org.is_default = true
        org.save
        created_organizations << org
        org
      end

      it 'redirects an org with a genuinely active (non-canceling) subscription to the plan-change UI instead of Stripe' do
        default_org.stripe_customer_id     = 'cus_redirect_active'
        default_org.stripe_subscription_id = 'sub_redirect_active'
        default_org.subscription_status    = 'active'
        default_org.save

        active_sub = build_subscription(
          'id' => 'sub_redirect_active',
          'status' => 'active',
          'cancel_at_period_end' => false
        )
        allow(Stripe::Subscription).to receive(:retrieve)
          .with('sub_redirect_active').and_return(active_sub)

        expect(Stripe::Checkout::Session).not_to receive(:create)

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(last_response.location).to eq("/billing/#{default_org.extid}/plans")
      end

      it 'allows checkout for an org mid currency-migration (subscription scheduled to cancel)' do
        default_org.stripe_customer_id     = 'cus_redirect_migration'
        default_org.stripe_subscription_id = 'sub_redirect_migration'
        default_org.subscription_status    = 'active'
        default_org.set_currency_migration_intent!('price_test', Time.now.to_i + 86_400)

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(last_response.location).to match(%r{\Ahttps://checkout\.stripe\.com/})
      end

      it 'allows checkout for an org with no subscription' do
        default_org # ensure the default org exists (no subscription state)

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(last_response.location).to match(%r{\Ahttps://checkout\.stripe\.com/})
      end
    end

    # =========================================================================
    # Regression coverage for the 2026-08-14 appsec review, finding H-2:
    # the checkout half. The portal half is covered under GET /billing/portal.
    #
    # A checkout started on this path is applied to the caller's default org:
    # it binds that org's Stripe Customer, and on completion the subscription
    # (and the member's payment instrument) lands on an organization the caller
    # does not own. The precondition is not exotic — JoinDomainOrganization
    # repoints a member's default_org_id at the shared tenant organization when
    # they sign in through that tenant's custom-domain SSO, and archives their
    # personal workspace, so the org this handler resolves is routinely one the
    # caller only belongs to.
    # =========================================================================
    context 'ownership gate on the redirect path (appsec H-2)' do
      let(:owner_org) do
        org            = Onetime::Organization.create!('Tenant Org', customer, customer.email)
        org.is_default = true
        org.save
        created_organizations << org
        org
      end

      # stripe_sandbox_api: false overrides the describe-level tag. This example
      # reaches the authorization gate and returns before any Stripe call, so it
      # needs neither the sandbox nor a cassette — and billing_spec_helper's
      # around hook skips every :stripe_sandbox_api example in CI (no real
      # STRIPE_API_KEY is configured there). Without the override this regression
      # test would silently never run on the branch it is meant to protect.
      it 'denies a non-owner member checkout on the organization', :vcr, stripe_sandbox_api: false do
        member = Onetime::Customer.create!(email: "checkout-member-#{SecureRandom.hex(4)}@example.com")
        created_customers << member
        member.save

        # Reproduce the repoint: an active 'member' whose default org is the
        # organization owned by someone else.
        owner_org.add_members_instance(member, through_attrs: { role: 'member', status: 'active' })
        member.default_org_id = owner_org.objid
        member.save

        # Give the org a Stripe customer but NO subscription: the duplicate-
        # subscription guard must not be what stops this request, or the test
        # would stay green with the authorization gate removed.
        owner_org.stripe_customer_id = 'cus_owner_only_checkout_fixture'
        owner_org.save

        env 'rack.session', {
          'authenticated' => true,
          'external_id' => member.extid,
        }

        expect(Stripe::Checkout::Session).not_to receive(:create)

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('billing_error=not_authorized')
        expect(last_response.location).not_to match(%r{\Ahttps://checkout\.stripe\.com/})
      end

      # Positive control: the gate must not over-block the legitimate owner.
      # Same fixture shape as the denial (org with a Stripe customer, no
      # subscription), so the only difference under test is ownership.
      #
      # Also pins the orgid stamp. Both completion paths resolve
      # metadata['orgid'] with Onetime::Organization.load, so the value must be
      # objid — extid or a nested debug_info key would silently fall through to
      # the default_org_id inference this stamp exists to replace.
      it 'still admits the organization owner and pins the target org by objid' do
        owner_org.stripe_customer_id = 'cus_owner_reuse_checkout_fixture'
        owner_org.save

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        expect(last_response.location).to match(%r{\Ahttps://checkout\.stripe\.com/})
        # The owner's session still binds the org's existing Stripe customer.
        expect(last_checkout_session.customer).to eq('cus_owner_reuse_checkout_fixture')

        metadata = last_checkout_session.subscription_data['metadata']
        expect(metadata['orgid']).to eq(owner_org.objid)
        expect(Onetime::Organization.load(metadata['orgid'])&.extid).to eq(owner_org.extid)
        # Purely additive: the historical keys are untouched.
        expect(metadata['customer_extid']).to eq(customer.extid)
        expect(JSON.parse(metadata['debug_info'])).to include('checkout_plan_id')
      end

      # When no default organization resolves, the key must be ABSENT rather
      # than empty: step 1 of find_target_organization treats any truthy
      # metadata['orgid'] as a lookup, and '' is truthy in Ruby, so an empty
      # stamp would burn a doomed Organization.load and log a spurious
      # 'orgid in metadata not found' before falling through.
      #
      # Reaching that branch takes an archived-only customer. A caller with
      # zero organizations never gets there: Controllers::Base#initialize runs
      # ensure_customer_has_workspace, which creates (and makes them owner of)
      # a workspace before this handler executes. Its `.any?` check counts
      # archived orgs, so it does not fire here — while
      # default_organization_for rejects them, yielding nil.
      it 'omits orgid entirely when no default organization resolves' do
        archived = Onetime::Organization.create!('Archived Org', customer, customer.email)
        created_organizations << archived
        archived.archive!('spec fixture: personal workspace superseded by SSO')

        get "/billing/plans/#{product}/#{interval}"

        expect(last_response.status).to eq(302)
        metadata = last_checkout_session.subscription_data['metadata'].to_hash
        expect(metadata.keys.map(&:to_s)).not_to include('orgid')
        expect(metadata.transform_keys(&:to_s)['customer_extid']).to eq(customer.extid)
      end
    end
  end

  describe 'GET /billing/welcome' do
    # identity_plus_v1's monthly price in apps/web/billing/spec/billing.test.yaml
    let(:catalog_price_id) { 'price_test_monthly' }

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

    # This and the archived-orgs example below are deliberately NOT
    # :stripe_sandbox_api. Every Stripe call they make is stubbed by
    # `with_stubbed_checkout`, so they need no API key and no cassette — and
    # the group-level tag would otherwise make CI skip them (see
    # BILLING_VCR_SKIP_IN_CI in spec/support/vcr_setup.rb). They are the only
    # CI coverage of /billing/welcome actually applying a subscription to an
    # organization; the sibling 'processes checkout session' example passes a
    # session with no subscription, so it returns before that code runs.
    #
    # This one covers the resolver's step 3: Billing::Controllers::Base
    # self-heals a 'Default Workspace' for the org-less customer during
    # initialize, and CheckoutTargetResolver then resolves it from the
    # customer's owned live orgs.
    it 'creates default organization for new customer', stripe_sandbox_api: false do
      # Price from apps/web/billing/spec/billing.test.yaml (identity_plus_v1),
      # loaded into the plan cache by `with_test_plans`. It must resolve
      # through the REAL catalog: ApplySubscriptionToOrg derives org.planid
      # from the price and then materializes entitlements from
      # Billing::Plan.load(planid). stub_test_plan_catalog! maps every
      # `price_test_*` id to a plan_id ('test_plan_v1') that `with_test_plans`
      # does not put in the cache, so leaving that stub in place fails
      # materialization with PlanCacheMissError (503).
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with(catalog_price_id)
        .and_call_original

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
        items: [{ price: catalog_price_id }],
        metadata: {
          customer_extid: new_customer.extid,
          plan_id: 'identity_plus_v1',
        },
      )

      checkout_session = Stripe::Checkout::Session.create(
        mode: 'subscription',
        customer: stripe_customer.id,
        subscription: subscription.id,
        line_items: [{ price: catalog_price_id, quantity: 1 }],
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

    # Step 4 of ProcessCheckoutSession#find_target_organization: nothing
    # resolved, so the paid subscription has to land on a workspace this
    # surface creates itself. Reaching it requires the customer to own only
    # ARCHIVED organizations: Billing::Controllers::Base#ensure_customer_has_workspace
    # counts archived orgs in its `.any?` guard so it creates nothing, while
    # CheckoutTargetResolver rejects them as billing targets. The archived org
    # also still holds the contact_email reservation, which is why
    # create_billing_workspace retries without one.
    it 'creates a billing workspace when only archived orgs remain', stripe_sandbox_api: false do
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with(catalog_price_id)
        .and_call_original

      new_customer = Onetime::Customer.create!(email: "archived-welcome-#{SecureRandom.hex(4)}@example.com")
      created_customers << new_customer
      new_customer.save

      archived = Onetime::Organization.create!('Archived Org', new_customer, new_customer.email)
      created_organizations << archived
      archived.archive!('spec fixture: no live billing target')

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => new_customer.extid,
      }

      stripe_customer = Stripe::Customer.create(email: new_customer.email)
      subscription    = Stripe::Subscription.create(
        customer: stripe_customer.id,
        items: [{ price: catalog_price_id }],
        metadata: {
          customer_extid: new_customer.extid,
          plan_id: 'identity_plus_v1',
        },
      )
      checkout_session = Stripe::Checkout::Session.create(
        mode: 'subscription',
        customer: stripe_customer.id,
        subscription: subscription.id,
        line_items: [{ price: catalog_price_id, quantity: 1 }],
        success_url: 'http://example.com/success',
        cancel_url: 'http://example.com/cancel',
      )

      get "/billing/welcome?session_id=#{checkout_session.id}"

      expect(last_response.status).to eq(302)

      created  = new_customer.organization_instances.to_a.reject(&:archived?)
      created_organizations.concat(created)

      expect(created.size).to eq(1)
      workspace = created.first
      # CheckoutTargetResolver#new_workspace naming, NOT CreateDefaultWorkspace's
      expect(workspace.display_name).to eq("#{new_customer.email}'s Workspace")
      expect(workspace.is_default).to be_truthy
      # The archived org kept the contact_email reservation, so the retry path ran
      expect(workspace.contact_email.to_s).to be_empty
      expect(workspace.planid).to eq('identity_plus_v1')
      expect(last_response.location).to eq("/billing/#{workspace.extid}/overview?upgraded=true")
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

    # ========================================================================
    # Regression coverage for the 2026-08-14 appsec review, finding H-2:
    # "Non-owner member is handed the organization's Stripe Customer Portal".
    #
    # The portal can read the full billing history, change the payment method
    # and cancel the subscription, so membership is not sufficient authority.
    # The precondition is not exotic: JoinDomainOrganization repoints a
    # member's default_org_id at the shared tenant organization when they sign
    # in through that tenant's custom-domain SSO, so the org this handler
    # resolves is routinely one the caller does not own.
    # ========================================================================
    # stripe_sandbox_api: false overrides the describe-level tag. This example
    # reaches the authorization gate and returns before any Stripe call, so it
    # needs neither the sandbox nor a cassette — and billing_spec_helper's
    # around hook skips every :stripe_sandbox_api example in CI (no real
    # STRIPE_API_KEY is configured there). Without the override this regression
    # test would silently never run on the branch it is meant to protect.
    it 'denies a non-owner member the organization portal', :vcr, stripe_sandbox_api: false do
      member = Onetime::Customer.create!(email: "portal-member-#{SecureRandom.hex(4)}@example.com")
      created_customers << member
      member.save

      # Reproduce the repoint: an active 'member' whose default org is the
      # organization owned by someone else.
      organization.add_members_instance(member, through_attrs: { role: 'member', status: 'active' })
      member.default_org_id = organization.objid
      member.save

      # Give the org a Stripe customer so the ONLY reason to redirect away is
      # the authorization gate — not the "no Stripe customer" branch, which
      # would also land on /account and could mask a missing check.
      organization.stripe_customer_id = 'cus_owner_only_fixture'
      organization.save

      env 'rack.session', {
        'authenticated' => true,
        'external_id' => member.extid,
      }

      get '/billing/portal'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to include('billing_error=not_authorized')
      expect(last_response.location).not_to match(%r{\Ahttps://billing\.stripe\.com/})
    end

    # Positive control: the gate must not over-block the legitimate owner.
    # Asserts the Stripe portal URL rather than merely "no billing_error",
    # because the handler's Stripe rescue also redirects to a plain /account
    # with no error param — so the weaker assertion would stay green even if
    # the owner never reached the portal at all.
    it 'still admits the organization owner', :vcr do
      stripe_customer                 = Stripe::Customer.create(email: organization.billing_email)
      organization.stripe_customer_id = stripe_customer.id
      organization.save

      get '/billing/portal'

      expect(last_response.status).to eq(302)
      expect(last_response.location).to match(%r{\Ahttps://billing\.stripe\.com/})
    end
  end
end

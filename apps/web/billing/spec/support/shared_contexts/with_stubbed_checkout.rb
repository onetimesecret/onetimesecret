# apps/web/billing/spec/support/shared_contexts/with_stubbed_checkout.rb
#
# frozen_string_literal: true

# Shared context for stubbing Stripe Checkout Session and related API calls.
#
# PURPOSE: Enable reliable testing of checkout and welcome flows without
# requiring real Stripe price IDs or API access.
#
# IMPORTANT EXCEPTION TO TESTING PHILOSOPHY:
# This is an intentional exception to our general rule of testing against
# the real Stripe API. We prefer real API integration tests because mocks
# can fail to identify issues that only the real API surfaces.
#
# However, checkout session creation requires valid price IDs that must:
# 1. Exist in the Stripe test account
# 2. Match the price_id values in spec/billing.test.yaml
# 3. Be kept in sync when products/prices change
#
# This coordination overhead makes real API testing impractical for:
# - Checkout redirect flow (GET /billing/plans/:product/:interval)
# - Welcome/post-checkout flow (GET /billing/welcome)
#
# Other billing tests (portal, webhooks) should continue using VCR with
# real API calls where the setup is more manageable.
#
# WHAT'S STUBBED:
# - Stripe::Customer.create → returns mock customer
# - Stripe::Subscription.create → returns mock subscription with metadata
# - Stripe::Checkout::Session.create → returns mock session
# - Stripe::Checkout::Session.retrieve → returns stored session with expanded data
#
# Usage:
#   RSpec.describe 'Plans Controller' do
#     include_context 'with_stubbed_checkout'
#
#     it 'creates checkout session' do
#       # All Stripe checkout-related calls are stubbed
#     end
#   end
#
RSpec.shared_context 'with_stubbed_checkout' do
  # Storage for created mock objects (keyed by ID)
  let(:stubbed_sessions) { {} }
  let(:stubbed_customers) { {} }
  let(:stubbed_subscriptions) { {} }

  before do
    stub_stripe_customer_create
    stub_stripe_subscription_create
    stub_stripe_checkout_session_create
    stub_stripe_checkout_session_retrieve
    stub_stripe_billing_portal_session_create
  end

  private

  # Stub Stripe::Customer.create
  def stub_stripe_customer_create
    allow(Stripe::Customer).to receive(:create) do |params|
      customer_id = "cus_stubbed_#{SecureRandom.hex(8)}"

      mock_customer = Stripe::Customer.construct_from({
        'id' => customer_id,
        'object' => 'customer',
        'email' => params[:email],
        'name' => params[:name],
        'metadata' => (params[:metadata] || {}).transform_keys(&:to_s),
        'created' => Time.now.to_i,
      })

      stubbed_customers[customer_id] = mock_customer
      mock_customer
    end
  end

  # Stub Stripe::Subscription.create
  def stub_stripe_subscription_create
    allow(Stripe::Subscription).to receive(:create) do |params|
      subscription_id = "sub_stubbed_#{SecureRandom.hex(8)}"

      # Build metadata with string keys
      metadata = (params[:metadata] || {}).transform_keys(&:to_s)

      # Period timestamps
      period_start = Time.now.to_i
      period_end = (Time.now + 30 * 24 * 60 * 60).to_i

      mock_subscription = Stripe::Subscription.construct_from({
        'id' => subscription_id,
        'object' => 'subscription',
        'customer' => params[:customer],
        'status' => 'active',
        'items' => {
          'object' => 'list',
          'data' => (params[:items] || []).map do |item|
            {
              'id' => "si_stubbed_#{SecureRandom.hex(4)}",
              'object' => 'subscription_item',
              'price' => { 'id' => item[:price] },
              'current_period_start' => period_start,
              'current_period_end' => period_end,
            }
          end,
        },
        'metadata' => metadata,
        'current_period_start' => period_start,
        'current_period_end' => period_end,
        'created' => Time.now.to_i,
      })

      stubbed_subscriptions[subscription_id] = mock_subscription
      mock_subscription
    end

    # Also stub retrieve for subscriptions
    allow(Stripe::Subscription).to receive(:retrieve) do |id, _opts = {}|
      stored = stubbed_subscriptions[id]
      if stored
        stored
      else
        raise Stripe::InvalidRequestError.new(
          "No such subscription: '#{id}'",
          'id',
          http_status: 404
        )
      end
    end
  end

  # Stub Stripe::Checkout::Session.create
  def stub_stripe_checkout_session_create
    allow(Stripe::Checkout::Session).to receive(:create) do |params|
      session_id = "cs_test_stubbed_#{SecureRandom.hex(12)}"

      # Build subscription_data with properly stringified keys
      subscription_data = nil
      if params[:subscription_data]
        sub_data = params[:subscription_data].transform_keys(&:to_s)
        if sub_data['metadata']
          sub_data['metadata'] = sub_data['metadata'].transform_keys(&:to_s)
        end
        subscription_data = sub_data
      end

      # If a subscription ID was passed, look it up
      subscription_obj = nil
      if params[:subscription]
        subscription_obj = stubbed_subscriptions[params[:subscription]]
      end

      # If a customer ID was passed, look it up
      customer_obj = nil
      if params[:customer]
        customer_obj = stubbed_customers[params[:customer]]
      end

      # Build mock session
      mock_session = Stripe::Checkout::Session.construct_from({
        'id' => session_id,
        'object' => 'checkout.session',
        'mode' => params[:mode] || 'subscription',
        'url' => "https://checkout.stripe.com/c/pay/#{session_id}",
        'success_url' => params[:success_url],
        'cancel_url' => params[:cancel_url],
        'customer_email' => params[:customer_email],
        'customer' => params[:customer],
        'client_reference_id' => params[:client_reference_id],
        'locale' => params[:locale],
        'subscription_data' => subscription_data,
        'subscription' => subscription_obj,
        'line_items' => params[:line_items]&.map { |li| li.transform_keys(&:to_s) },
        'status' => 'complete',
        'payment_status' => 'paid',
      })

      # Store with expanded objects for retrieve
      stubbed_sessions[session_id] = {
        session: mock_session,
        customer: customer_obj,
        subscription: subscription_obj,
      }

      mock_session
    end
  end

  # Stub Stripe::Checkout::Session.retrieve
  # Handles expand parameter to return nested objects
  def stub_stripe_checkout_session_retrieve
    allow(Stripe::Checkout::Session).to receive(:retrieve) do |id_or_params, _opts = {}|
      # Handle both retrieve(id) and retrieve({id:, expand:}) forms
      if id_or_params.is_a?(Hash)
        session_id = id_or_params[:id]
        expand = id_or_params[:expand] || []
      else
        session_id = id_or_params
        expand = []
      end

      stored = stubbed_sessions[session_id]

      unless stored
        raise Stripe::InvalidRequestError.new(
          "No such checkout session: '#{session_id}'",
          'id',
          http_status: 404
        )
      end

      session = stored[:session]

      # Handle expand parameter - replace IDs with full objects
      if expand.include?('subscription') && stored[:subscription]
        # Update the session's subscription field with full object
        session_data = session.to_hash
        session_data['subscription'] = stored[:subscription]
        session = Stripe::Checkout::Session.construct_from(session_data)
      end

      if expand.include?('customer') && stored[:customer]
        session_data = session.to_hash
        session_data['customer'] = stored[:customer]
        session = Stripe::Checkout::Session.construct_from(session_data)
      end

      session
    end
  end

  # Stub Stripe::BillingPortal::Session.create
  # Raises error for 'cus_invalid' to test error handling
  def stub_stripe_billing_portal_session_create
    allow(Stripe::BillingPortal::Session).to receive(:create) do |params|
      # Simulate error for invalid customer IDs (for testing error handling)
      if params[:customer]&.start_with?('cus_invalid')
        raise Stripe::InvalidRequestError.new(
          "No such customer: '#{params[:customer]}'",
          'customer',
          http_status: 404
        )
      end

      portal_session_id = "bps_stubbed_#{SecureRandom.hex(12)}"

      Stripe::BillingPortal::Session.construct_from({
        'id' => portal_session_id,
        'object' => 'billing_portal.session',
        'customer' => params[:customer],
        'url' => "https://billing.stripe.com/p/session/#{portal_session_id}",
        'return_url' => params[:return_url],
        'created' => Time.now.to_i,
        'livemode' => false,
      })
    end
  end

  public

  # Helper: Get the last created checkout session
  def last_checkout_session
    stubbed_sessions.values.last&.dig(:session)
  end

  # Helper: Get all created checkout sessions
  def all_checkout_sessions
    stubbed_sessions.values.map { |s| s[:session] }
  end

  # Helper: Get a stored subscription by ID
  def get_stubbed_subscription(id)
    stubbed_subscriptions[id]
  end

  # Helper: Get a stored customer by ID
  def get_stubbed_customer(id)
    stubbed_customers[id]
  end
end

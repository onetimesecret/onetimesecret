# apps/web/billing/spec/operations/create_checkout_link_spec.rb
#
# frozen_string_literal: true

# Unit tests for CreateCheckoutLink operation.
#
# Covers:
# - happy path: session created, result fields populated, ColonelAuditEvent
#   recorded, and — CRITICALLY — subscription_data.metadata carries
#   customer_extid + orgid (the checkout.session.completed handler reads ONLY
#   those and skips the event without them)
# - customer vs customer_email branch (existing Stripe customer wins and the
#   email param is removed, making the email read-only in Checkout)
# - automatic tax (config-driven via billing_config.automatic_tax?):
#   automatic_tax + billing_address_collection always, customer_update only
#   with :customer; omitted entirely when the config is off
# - payment method configuration (config-driven via
#   billing_config.payment_method_configuration): pins the session to a
#   pmc_... id when set; key entirely absent when unset
# - dry_run: :would_create with the resolved price id, no Stripe call
# - failures: billing disabled, Stripe unconfigured, plan resolution failure,
#   missing price for interval, region mismatch
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/create_checkout_link_spec.rb

require_relative '../support/billing_spec_helper'
require 'stripe'
require_relative '../../operations/create_checkout_link'

RSpec.describe Billing::Operations::CreateCheckoutLink do
  include_context 'with_stubbed_checkout'

  let(:customer) do
    double('Customer', extid: 'ur_target', email: 'target@example.com')
  end

  let(:stripe_customer_id) { nil }

  # Duplicate-subscription guard inputs (issue #2605). Default: no
  # subscription, so the guard is a no-op for every other example.
  let(:active_subscription)     { false }
  let(:stripe_subscription_id)  { nil }
  let(:pending_migration)       { false }

  let(:org) do
    double('Organization',
      objid: 'org_obj_1',
      extid: 'org_ext_1',
      billing_email: nil,
      stripe_customer_id: stripe_customer_id,
      active_subscription?: active_subscription,
      stripe_subscription_id: stripe_subscription_id,
      pending_currency_migration?: pending_migration,
    )
  end

  let(:price_data) { { 'stripe_price_id' => 'price_test_123' } }

  let(:plan) do
    double('Billing::Plan',
      plan_id: 'identity_plus_v1',
      tier: 'identity',
      region: 'EU',
      price_for: price_data,
    )
  end

  let(:resolution) do
    Billing::PlanResolver::Result.new(
      success: true,
      plan_id: 'identity_plus_v1',
      tier: 'identity',
      billing_cycle: 'monthly',
      plan: plan,
      error: nil,
    )
  end

  let(:deployment_region)             { nil }
  let(:automatic_tax)                 { false }
  let(:payment_method_configuration)  { nil }

  def call_op(**overrides)
    described_class.call(
      **{
        customer: customer,
        org: org,
        product: 'identity_plus_v1',
        interval: 'monthly',
        actor: 'ur_colonel',
      }.merge(overrides),
    )
  end

  before do
    allow(Onetime.billing_config).to receive_messages(
      enabled?: true,
      stripe_key: 'sk_test_mock',
      region: deployment_region,
      automatic_tax?: automatic_tax,
      payment_method_configuration: payment_method_configuration,
    )
    allow(Onetime).to receive(:conf).and_return(
      'site' => { 'host' => 'test.example.com', 'ssl' => true },
      'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } },
    )
    allow(Billing::PlanResolver).to receive(:resolve).and_return(resolution)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe 'happy path' do
    it 'creates a session and returns the checkout URL' do
      result = call_op

      expect(result.created?).to be(true)
      expect(result.url).to start_with('https://checkout.stripe.com/')
      expect(result.session_id).to start_with('cs_test_stubbed_')
      expect(result.price_id).to eq('price_test_123')
      expect(result.plan_id).to eq('identity_plus_v1')
      expect(result.expires_at).to be_within(60).of(Time.now.to_i + described_class::SESSION_TTL)
    end

    # The webhook handler (checkout_completed) reads ONLY
    # subscription.metadata['customer_extid'] and metadata['orgid'] — without
    # them the completed event is silently skipped and the paid subscription
    # never attaches. This is the load-bearing assertion of the whole op.
    it 'stamps customer_extid and orgid into subscription_data.metadata' do
      call_op

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          subscription_data: {
            metadata: hash_including(
              customer_extid: 'ur_target',
              orgid: 'org_obj_1',
              plan_id: 'identity_plus_v1',
              tier: 'identity',
              region: 'EU',
            ),
          },
        ),
        anything,
      )
    end

    it 'binds the session to the customer email and org reference' do
      call_op

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          customer_email: 'target@example.com',
          client_reference_id: 'org_obj_1',
          mode: 'subscription',
          line_items: [{ price: 'price_test_123', quantity: 1 }],
          success_url: 'https://test.example.com/billing/welcome?session_id={CHECKOUT_SESSION_ID}',
          cancel_url: 'https://test.example.com/pricing',
          allow_promotion_codes: false,
        ),
        anything,
      )
    end

    it 'records one ColonelAuditEvent with actor, target and session id' do
      result = call_op

      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        actor: 'ur_colonel',
        verb: described_class::AUDIT_VERB,
        target: 'ur_target',
        result: :success,
        detail: {
          plan_id: 'identity_plus_v1',
          session_id: result.session_id,
          org_extid: 'org_ext_1',
        },
      )
    end
  end

  describe 'existing Stripe customer' do
    let(:stripe_customer_id) { 'cus_existing_123' }

    # Passing :customer (like :customer_email) makes the email read-only in
    # Checkout — the point of a support-issued link.
    it 'passes :customer and drops :customer_email' do
      call_op

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(customer: 'cus_existing_123'),
        anything,
      )
      expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
        expect(params).not_to have_key(:customer_email)
      end
    end

  end

  # Automatic tax is deployment policy (STRIPE_AUTOMATIC_TAX / billing.yaml
  # 'automatic_tax'), never a per-call choice — there is no parameter for it.
  describe 'automatic tax (config-driven)' do
    context 'when billing_config.automatic_tax? is enabled' do
      let(:automatic_tax) { true }

      context 'with an existing Stripe customer' do
        let(:stripe_customer_id) { 'cus_existing_123' }

        it 'adds automatic_tax, billing_address_collection AND customer_update' do
          call_op

          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(
              automatic_tax: { enabled: true },
              billing_address_collection: 'required',
              tax_id_collection: { enabled: true },
              customer_update: { address: 'auto' },
            ),
            anything,
          )
        end
      end

      context 'without an existing Stripe customer' do
        it 'adds automatic_tax and billing_address_collection but NOT customer_update' do
          call_op

          expect(Stripe::Checkout::Session).to have_received(:create).with(
            hash_including(
              automatic_tax: { enabled: true },
              billing_address_collection: 'required',
              tax_id_collection: { enabled: true },
            ),
            anything,
          )
          expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
            expect(params).not_to have_key(:customer_update)
          end
        end
      end
    end

    context 'when billing_config.automatic_tax? is disabled' do
      it 'omits the automatic_tax params entirely' do
        call_op

        expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
          expect(params).not_to have_key(:automatic_tax)
          expect(params).not_to have_key(:billing_address_collection)
          expect(params).not_to have_key(:tax_id_collection)
          expect(params).not_to have_key(:customer_update)
        end
      end
    end
  end

  # The payment-method-configuration pin is deployment policy
  # (STRIPE_PAYMENT_METHOD_CONFIGURATION / billing.yaml
  # 'payment_method_configuration'), never a per-call choice — there is no
  # parameter for it.
  describe 'payment method configuration (config-driven)' do
    context 'when billing_config.payment_method_configuration is set' do
      let(:payment_method_configuration) { 'pmc_test_abc123' }

      it 'pins the session to the configured pmc id' do
        call_op

        expect(Stripe::Checkout::Session).to have_received(:create).with(
          hash_including(payment_method_configuration: 'pmc_test_abc123'),
          anything,
        )
      end
    end

    context 'when billing_config.payment_method_configuration is nil' do
      it 'omits the key entirely (Stripe falls back to the Dashboard default)' do
        call_op

        expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
          expect(params).not_to have_key(:payment_method_configuration)
        end
      end
    end
  end

  # ADR-033 / issue #4013: boot only format-checks the configured pmc id;
  # existence in the connected Stripe account is discovered at first use.
  # That discovery must produce a pointed operator log WITHOUT changing the
  # generic outward failure, and must not fire for any other Stripe error.
  describe 'payment_method_configuration resource_missing discrimination (issue #4013)' do
    let(:payment_method_configuration) { 'pmc_test_abc123' }

    before { allow(OT).to receive(:le) }

    def stub_resource_missing(message, param)
      allow(Stripe::Checkout::Session).to receive(:create).and_raise(
        Stripe::InvalidRequestError.new(
          message, param, http_status: 400, code: 'resource_missing'
        ),
      )
    end

    context 'when Stripe reports the configured pmc does not exist' do
      before do
        stub_resource_missing(
          "No such payment method configuration: 'pmc_test_abc123'",
          'payment_method_configuration',
        )
      end

      it 'logs a pointed operator error naming the value, causes, and config source' do
        call_op

        expect(OT).to have_received(:le).with(
          a_string_including('"pmc_test_abc123"')
            .and(a_string_including('does not exist in the connected Stripe account'))
            .and(a_string_including('live/test mode mismatch'))
            .and(a_string_including('STRIPE_PAYMENT_METHOD_CONFIGURATION')),
        )
      end

      it 'leaves the outward failure exactly as generic as any other Stripe error' do
        result = call_op

        expect(result.failed?).to be(true)
        expect(result.reason).to eq(
          "Stripe error: No such payment method configuration: 'pmc_test_abc123'",
        )
        expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
      end
    end

    context 'when resource_missing names a DIFFERENT param' do
      before { stub_resource_missing("No such customer: 'cus_nope'", 'customer') }

      it 'does not emit the pmc log line and fails identically to before' do
        result = call_op

        expect(OT).not_to have_received(:le)
        expect(result.failed?).to be(true)
        expect(result.reason).to eq("Stripe error: No such customer: 'cus_nope'")
      end
    end
  end

  # Issue #2605 / review finding: a support-issued link is NOT an exemption
  # from the duplicate-subscription guard. Completing a second checkout
  # creates a second live Stripe subscription and the webhook overwrites
  # org.stripe_subscription_id — double charge + orphaned subscription.
  describe 'duplicate-subscription guard' do
    let(:active_subscription)    { true }
    let(:stripe_subscription_id) { 'sub_active_guard' }

    before { allow(Stripe).to receive(:api_key).and_return('sk_test_mock') }

    def stub_subscription(cancel_at_period_end:, status: 'active')
      allow(Stripe::Subscription).to receive(:retrieve).with('sub_active_guard').and_return(
        Stripe::Subscription.construct_from(
          'id' => 'sub_active_guard',
          'object' => 'subscription',
          'status' => status,
          'cancel_at_period_end' => cancel_at_period_end,
        ),
      )
    end

    it 'refuses to create a session when the org already has an active subscription' do
      stub_subscription(cancel_at_period_end: false)

      result = call_op

      expect(result.failed?).to be(true)
      expect(result.reason).to eq('Organization already has an active subscription')
      expect(Stripe::Checkout::Session).not_to have_received(:create)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end

    it 'reports the block on a dry run instead of a link it would refuse' do
      stub_subscription(cancel_at_period_end: false)

      result = call_op(dry_run: true)

      expect(result.failed?).to be(true)
      expect(result.reason).to eq('Organization already has an active subscription')
    end

    it 'allows the link when the subscription is scheduled to cancel' do
      stub_subscription(cancel_at_period_end: true)

      expect(call_op.created?).to be(true)
    end

    context 'during a pending currency migration' do
      let(:pending_migration) { true }

      it 'allows the link (the old subscription is winding down)' do
        expect(call_op.created?).to be(true)
      end
    end

    context 'when the org owns no Stripe subscription (federated)' do
      let(:stripe_subscription_id) { '' }

      it 'allows the link' do
        expect(call_op.created?).to be(true)
      end
    end

    # Fail-safe: an unverifiable subscription state blocks rather than risking
    # a duplicate charge.
    it 'blocks when the subscription state cannot be verified' do
      allow(Stripe::Subscription).to receive(:retrieve)
        .and_raise(Stripe::APIConnectionError.new('timeout'))

      result = call_op
      expect(result.failed?).to be(true)
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end
  end

  describe 'dry_run' do
    it 'returns :would_create with the resolved price and makes no Stripe call' do
      result = call_op(dry_run: true)

      expect(result.would_create?).to be(true)
      expect(result.skipped?).to be(true)
      expect(result.price_id).to eq('price_test_123')
      expect(result.plan_id).to eq('identity_plus_v1')
      expect(result.url).to be_nil
      expect(Stripe::Checkout::Session).not_to have_received(:create)
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end

  describe 'failures' do
    it 'fails when billing is not enabled' do
      allow(Onetime.billing_config).to receive(:enabled?).and_return(false)

      result = call_op
      expect(result.failed?).to be(true)
      expect(result.reason).to eq('Billing is not enabled')
    end

    it 'fails when Stripe is not configured' do
      allow(Onetime.billing_config).to receive(:stripe_key).and_return(nil)

      result = call_op
      expect(result.failed?).to be(true)
      expect(result.reason).to eq('Stripe is not configured')
    end

    it 'fails when plan resolution fails' do
      allow(Billing::PlanResolver).to receive(:resolve).and_return(
        Billing::PlanResolver::Result.new(
          success: false, plan_id: nil, tier: nil, billing_cycle: nil,
          plan: nil, error: 'Plan not found: bogus_v1',
        ),
      )

      result = call_op(product: 'bogus_v1')
      expect(result.failed?).to be(true)
      expect(result.reason).to eq('Plan not found: bogus_v1')
      expect(Stripe::Checkout::Session).not_to have_received(:create)
    end

    it 'fails when the plan has no price for the interval' do
      allow(plan).to receive(:price_for).and_return(nil)

      result = call_op
      expect(result.failed?).to be(true)
      expect(result.reason).to eq('No price available for monthly billing')
    end

    context 'when the deployment is region-scoped' do
      let(:deployment_region) { 'CA' }

      it 'refuses a plan from another region' do
        result = call_op

        expect(result.failed?).to be(true)
        expect(result.reason).to eq('Plan region EU does not match deployment region CA')
        expect(Stripe::Checkout::Session).not_to have_received(:create)
      end
    end

    it 'returns failed on a Stripe error instead of raising' do
      allow(Stripe::Checkout::Session).to receive(:create)
        .and_raise(Stripe::InvalidRequestError.new('No such price', 'price'))

      result = call_op
      expect(result.failed?).to be(true)
      expect(result.reason).to include('No such price')
      expect(Onetime::ColonelAuditEvent).not_to have_received(:record)
    end
  end
end

# apps/web/billing/spec/operations/create_checkout_link_spec.rb
#
# frozen_string_literal: true

# Unit tests for CreateCheckoutLink operation.
#
# Covers:
# - happy path: session created, result fields populated, AdminAuditEvent
#   recorded, and — CRITICALLY — subscription_data.metadata carries
#   customer_extid + orgid (the checkout.session.completed handler reads ONLY
#   those and skips the event without them)
# - customer vs customer_email branch (existing Stripe customer wins and the
#   email param is removed, making the email read-only in Checkout)
# - enable_tax: automatic_tax always, customer_update only with :customer
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

  let(:org) do
    double('Organization',
      objid: 'org_obj_1',
      extid: 'org_ext_1',
      billing_email: nil,
      stripe_customer_id: stripe_customer_id,
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

  let(:deployment_region) { nil }

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
    )
    allow(Onetime).to receive(:conf).and_return(
      'site' => { 'host' => 'test.example.com', 'ssl' => true },
      'features' => { 'regions' => { 'current_jurisdiction' => 'EU' } },
    )
    allow(Billing::PlanResolver).to receive(:resolve).and_return(resolution)
    allow(Onetime::AdminAuditEvent).to receive(:record)
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

    it 'records one AdminAuditEvent with actor, target and session id' do
      result = call_op

      expect(Onetime::AdminAuditEvent).to have_received(:record).with(
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

    it 'adds automatic_tax AND customer_update when enable_tax is set' do
      call_op(enable_tax: true)

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(
          automatic_tax: { enabled: true },
          customer_update: { address: 'auto' },
        ),
        anything,
      )
    end
  end

  describe 'enable_tax without an existing Stripe customer' do
    it 'adds automatic_tax but NOT customer_update' do
      call_op(enable_tax: true)

      expect(Stripe::Checkout::Session).to have_received(:create).with(
        hash_including(automatic_tax: { enabled: true }),
        anything,
      )
      expect(Stripe::Checkout::Session).to have_received(:create) do |params, _opts|
        expect(params).not_to have_key(:customer_update)
      end
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
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
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
      expect(Onetime::AdminAuditEvent).not_to have_received(:record)
    end
  end
end

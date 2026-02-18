# apps/web/billing/spec/operations/process_webhook_event/checkout_completed_spec.rb
#
# frozen_string_literal: true

# Tests for checkout.session.completed webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/checkout_completed_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: checkout.session.completed', :integration, :process_webhook_event do
  let(:test_email) { "checkout-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_checkout_123' }
  let(:stripe_subscription_id) { 'sub_checkout_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  # Helper to build mock Stripe::Customer for federation stubs
  def build_stripe_customer_mock(id:, email:, metadata: {})
    double('Stripe::Customer', id: id, email: email, metadata: metadata)
  end

  # Shared setup: stub Stripe::Customer.retrieve for all checkout tests
  # This prevents VCR from recording 404s for mock customer IDs
  before do
    stripe_customer = build_stripe_customer_mock(
      id: stripe_customer_id,
      email: test_email,
      metadata: {},
    )
    allow(Stripe::Customer).to receive(:retrieve)
      .with(stripe_customer_id)
      .and_return(stripe_customer)
    allow(Stripe::Customer).to receive(:update)
      .and_return(stripe_customer)
  end

  let(:session) do
    build_stripe_session(
      id: 'cs_test_123',
      customer: stripe_customer_id,
      subscription: stripe_subscription_id,
    )
  end

  let(:event) { build_stripe_event(type: 'checkout.session.completed', data_object: session) }
  let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  context 'with valid subscription checkout' do
    let!(:customer) { create_test_customer(email: test_email) }

    # Build subscription with actual customer custid
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription)
    end

    include_examples 'handles event successfully'

    it 'creates default organization for customer without one' do
      expect { operation.call }.to change {
        customer.organization_instances.to_a.length
      }.from(0).to(1)
    end

    it 'updates organization with subscription details' do
      operation.call
      org = customer.organization_instances.to_a.first
      expect(org.stripe_subscription_id).to eq(stripe_subscription_id)
      expect(org.subscription_status).to eq('active')
    end

    it 'uses existing default organization if present' do
      existing_org = create_test_organization(customer: customer, default: true)
      expect { operation.call }.not_to(change { customer.organization_instances.to_a.length })
      existing_org.refresh!
      expect(existing_org.stripe_subscription_id).to eq(stripe_subscription_id)
    end
  end

  # ============================================================================
  # Catalog-First Plan Resolution Tests
  # ============================================================================
  #
  # With catalog-first design, plan_id is resolved from the Stripe price catalog
  # (via Billing::PlanValidator.resolve_plan_id). Subscription metadata is used
  # only for debugging and drift detection.
  #
  # @see Billing::PlanValidator.resolve_plan_id
  # @see WithOrganizationBilling#extract_plan_id_from_subscription

  context 'with plan_id in subscription metadata (drift scenario)' do
    let!(:customer) { create_test_customer(email: test_email) }

    let(:subscription_with_planid) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: {
          'customer_extid' => customer.extid,
          Billing::Metadata::FIELD_PLAN_ID => 'identity_plus_v1',
        },
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription_with_planid)
    end

    it 'sets organization planid from catalog (ignoring metadata)' do
      operation.call
      org = customer.organization_instances.to_a.first
      # Catalog-first: plan_id comes from catalog, not metadata
      expect(org.planid).to eq('test_plan_v1_monthly')
    end

    it 'logs drift warning when metadata differs from catalog' do
      expect(OT).to receive(:lw).with(
        a_string_including('Drift detected'),
        hash_including(
          catalog_plan_id: 'test_plan_v1_monthly',
          metadata_plan_id: 'identity_plus_v1',
        ),
      )
      operation.call
    end
  end

  context 'with plan_id only in price metadata (drift scenario)' do
    let!(:customer) { create_test_customer(email: test_email) }

    let(:subscription_with_price_planid) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => customer.extid },
        price_metadata: { Billing::Metadata::FIELD_PLAN_ID => 'multi_team_v1' },
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription_with_price_planid)
    end

    it 'sets organization planid from catalog (ignoring price metadata)' do
      operation.call
      org = customer.organization_instances.to_a.first
      # Catalog-first: plan_id comes from catalog, not price metadata
      expect(org.planid).to eq('test_plan_v1_monthly')
    end
  end

  context 'with price_id not in catalog (fail-closed)' do
    let!(:customer) { create_test_customer(email: test_email) }

    let(:subscription_uncataloged) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => customer.extid },
        price_metadata: {},
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription_uncataloged)
      # Override catalog stub to return nil for 'price_test' (the default price_id)
      # This simulates a price that exists in Stripe but hasn't been cataloged locally
      allow(Billing::Plan).to receive(:find_by_stripe_price_id)
        .with('price_test')
        .and_return(nil)
    end

    it 'raises CatalogMissError (fail-closed design)' do
      expect { operation.call }.to raise_error(Billing::CatalogMissError)
    end
  end

  context 'with one-time payment (no subscription)' do
    let(:payment_session) do
      build_stripe_session(id: 'cs_payment', customer: stripe_customer_id, subscription: nil, mode: 'payment')
    end
    let(:event) { build_stripe_event(type: 'checkout.session.completed', data_object: payment_session) }

    it 'returns :skipped for one-time payments' do
      expect(operation.call).to eq(:skipped)
    end

    it 'does not call Stripe API' do
      expect(Stripe::Subscription).not_to receive(:retrieve)
      operation.call
    end
  end

  context 'with missing customer_extid in metadata' do
    let(:subscription_no_customer_extid) do
      build_stripe_subscription(id: stripe_subscription_id, customer: stripe_customer_id, status: 'active', metadata: {})
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription_no_customer_extid)
    end

    it 'returns :skipped when customer_extid is missing' do
      expect(operation.call).to eq(:skipped)
    end
  end

  context 'with invalid customer_extid format' do
    let(:subscription_invalid_customer_extid) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => '../../../etc/passwd' }, # Malformed input
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription_invalid_customer_extid)
    end

    it 'returns :skipped when customer_extid format is invalid' do
      expect(operation.call).to eq(:skipped)
    end

    it 'does not attempt to load customer' do
      expect(Onetime::Customer).not_to receive(:load)
      operation.call
    end
  end

  context 'with missing customer record' do
    let(:subscription_missing_customer) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => 'urnonexistent00000000000000' },
      )
    end

    before do
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription_missing_customer)
    end

    it 'returns :not_found when customer does not exist' do
      expect(operation.call).to eq(:not_found)
    end
  end

  # ============================================================================
  # Email Hash Federation Tests
  # ============================================================================
  #
  # Tests for setting email_hash in Stripe customer metadata at checkout completion.
  # This enables cross-region subscription federation.
  #
  # @see Onetime::Utils::EmailHash
  # @see Billing::Operations::WebhookHandlers::SubscriptionFederation

  describe 'email_hash federation' do
    let!(:customer) { create_test_customer(email: test_email) }
    let(:stripe_customer_email) { 'subscriber@example.com' }

    let(:stripe_customer) do
      build_customer(
        'id' => stripe_customer_id,
        'email' => stripe_customer_email,
        'metadata' => {},
      )
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    before do
      # Stub FEDERATION_SECRET for email hash computation
      ENV['FEDERATION_SECRET'] ||= 'test-hmac-secret-for-federation'

      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription)
    end

    context 'when Stripe customer has no email_hash in metadata' do
      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)
        allow(Stripe::Customer).to receive(:update)
          .and_return(stripe_customer)
      end

      it 'sets email_hash in Stripe customer metadata' do
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          hash_including(
            metadata: hash_including(
              'email_hash' => a_string_matching(/\A[0-9a-f]{32}\z/),
              'email_hash_created_at' => a_string_matching(/\A\d+\z/),
              'home_region' => anything,
            ),
          ),
        )
        operation.call
      end

      it 'computes email_hash from Stripe customer email' do
        expected_hash = Onetime::Utils::EmailHash.compute(stripe_customer_email)
        expect(Stripe::Customer).to receive(:update).with(
          stripe_customer_id,
          hash_including(
            metadata: hash_including('email_hash' => expected_hash),
          ),
        )
        operation.call
      end
    end

    context 'when Stripe customer already has email_hash (immutability)' do
      let(:existing_hash) { 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4' }
      let(:stripe_customer_with_hash) do
        build_customer(
          'id' => stripe_customer_id,
          'email' => stripe_customer_email,
          'metadata' => { 'email_hash' => existing_hash },
        )
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer_with_hash)
      end

      it 'does NOT overwrite existing email_hash' do
        expect(Stripe::Customer).not_to receive(:update)
        operation.call
      end

      it 'still returns :success' do
        expect(operation.call).to eq(:success)
      end
    end

    context 'when Stripe customer has no email' do
      let(:stripe_customer_no_email) do
        build_customer(
          'id' => stripe_customer_id,
          'email' => nil,
          'metadata' => {},
        )
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer_no_email)
      end

      it 'does NOT set email_hash (cannot compute without email)' do
        expect(Stripe::Customer).not_to receive(:update)
        operation.call
      end

      it 'still returns :success (federation is secondary)' do
        expect(operation.call).to eq(:success)
      end
    end

    context 'when Stripe API call fails' do
      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_raise(Stripe::APIConnectionError.new('Connection refused'))
      end

      it 'does NOT fail the checkout (federation is secondary)' do
        expect { operation.call }.not_to raise_error
      end

      it 'still returns :success' do
        expect(operation.call).to eq(:success)
      end
    end

    context 'organization email_hash computation' do
      let!(:existing_org) do
        org = create_test_organization(customer: customer, default: true)
        org.billing_email = 'org-billing@example.com'
        org.save
        org
      end

      before do
        allow(Stripe::Customer).to receive(:retrieve)
          .with(stripe_customer_id)
          .and_return(stripe_customer)
        allow(Stripe::Customer).to receive(:update)
          .and_return(stripe_customer)
      end

      it 'computes email_hash for organization if not present' do
        expect(existing_org.email_hash).to be_nil
        operation.call
        existing_org.refresh!
        expect(existing_org.email_hash).not_to be_nil
        expect(existing_org.email_hash.length).to eq(32)
        expect(existing_org.email_hash).to match(/\A[0-9a-f]{32}\z/)
      end

      it 'does NOT overwrite existing organization email_hash' do
        existing_org.email_hash = 'existing_org_hash_value_1234567'
        existing_org.save

        operation.call
        existing_org.refresh!
        expect(existing_org.email_hash).to eq('existing_org_hash_value_1234567')
      end
    end
  end
end

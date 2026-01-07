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

  context 'with plan_id in subscription metadata' do
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

    it 'sets organization planid from subscription metadata' do
      operation.call
      org = customer.organization_instances.to_a.first
      expect(org.planid).to eq('identity_plus_v1')
    end
  end

  context 'with plan_id only in price metadata' do
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

    it 'sets organization planid from price metadata as fallback' do
      operation.call
      org = customer.organization_instances.to_a.first
      expect(org.planid).to eq('multi_team_v1')
    end
  end

  context 'with no plan_id in any metadata or catalog' do
    let!(:customer) { create_test_customer(email: test_email) }

    let(:subscription_no_planid) do
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
        .and_return(subscription_no_planid)
      # Empty catalog - price_id fallback also fails
      allow(Billing::Plan).to receive(:list_plans).and_return([])
    end

    it 'logs warning when no plan_id found in metadata or catalog' do
      expect(OT).to receive(:lw).with(
        a_string_including('Unable to resolve plan_id'),
        hash_including(price_id: 'price_test', subscription_id: stripe_subscription_id)
      )
      operation.call
    end

    it 'organization keeps default planid' do
      allow(OT).to receive(:lw) # Suppress warning output
      operation.call
      org = customer.organization_instances.to_a.first
      # Organization has default planid of 'free' when no plan_id is extracted
      expect(org.planid).to eq('free')
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
end

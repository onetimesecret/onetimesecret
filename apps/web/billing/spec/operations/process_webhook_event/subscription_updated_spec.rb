# apps/web/billing/spec/operations/process_webhook_event/subscription_updated_spec.rb
#
# frozen_string_literal: true

# Tests for customer.subscription.updated webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/subscription_updated_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.subscription.updated', :integration, :process_webhook_event do
  let(:test_email) { "updated-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_updated_123' }
  let(:stripe_subscription_id) { 'sub_updated_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  # Helper to build mock Stripe::Customer for federation stubs
  def build_stripe_customer(id:, email:, metadata: {})
    double('Stripe::Customer', id: id, email: email, metadata: metadata)
  end

  context 'with existing organization' do
    let!(:customer) { create_test_customer(email: test_email) }
    let!(:organization) do
      org = create_test_organization(customer: customer)
      org.stripe_subscription_id = stripe_subscription_id
      org.subscription_status = 'active'
      org.save
      org
    end

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'past_due',
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(organization)

      # Stub Stripe::Customer.retrieve for federation lookup
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: test_email,
        metadata: {},
      )
      allow(Stripe::Customer).to receive(:retrieve)
        .with(stripe_customer_id)
        .and_return(stripe_customer)

      # Stub federation lookups
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(organization)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
        .and_return([])
    end

    include_examples 'handles event successfully'

    it 'updates subscription status on organization' do
      operation.call
      organization.refresh!
      expect(organization.subscription_status).to eq('past_due')
    end
  end

  context 'with unknown organization' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'past_due',
        metadata: { 'customer_extid' => 'unknown_extid' },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(nil)

      # Stub Stripe::Customer.retrieve for federation lookup
      stripe_customer = build_stripe_customer(
        id: stripe_customer_id,
        email: 'unknown@example.com',
        metadata: {},
      )
      allow(Stripe::Customer).to receive(:retrieve)
        .with(stripe_customer_id)
        .and_return(stripe_customer)

      # Stub federation lookups (no matches)
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(nil)
      allow(Onetime::Organization).to receive(:find_federated_by_email_hash)
        .and_return([])
    end

    include_examples 'logs warning for missing organization'
  end
end

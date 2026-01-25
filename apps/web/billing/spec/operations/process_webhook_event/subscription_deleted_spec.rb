# apps/web/billing/spec/operations/process_webhook_event/subscription_deleted_spec.rb
#
# frozen_string_literal: true

# Tests for customer.subscription.deleted webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/subscription_deleted_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.subscription.deleted', :integration, :process_webhook_event do
  let(:test_email) { "deleted-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_deleted_123' }
  let(:stripe_subscription_id) { 'sub_deleted_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
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
        status: 'canceled',
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.deleted', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(organization)
    end

    include_examples 'handles event successfully'

    it 'clears stripe_subscription_id' do
      operation.call
      organization.refresh!
      expect(organization.stripe_subscription_id).to be_nil
    end

    it 'sets subscription_status to canceled' do
      operation.call
      organization.refresh!
      expect(organization.subscription_status).to eq('canceled')
    end
  end

  context 'with unknown organization' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'canceled',
        metadata: { 'customer_extid' => 'unknown_extid' },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.deleted', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(nil)
    end

    include_examples 'logs warning for missing organization'
  end
end

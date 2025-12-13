# apps/web/billing/spec/operations/process_webhook_event/subscription_paused_spec.rb
#
# frozen_string_literal: true

# Tests for customer.subscription.paused webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/subscription_paused_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.subscription.paused', :integration, :process_webhook_event do
  let(:test_email) { "paused-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_paused_123' }
  let(:stripe_subscription_id) { 'sub_paused_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  context 'with existing organization' do
    let!(:customer) { create_test_customer(custid: nil, email: test_email) }
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
        status: 'paused',
        metadata: { 'custid' => customer.custid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.paused', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(organization)
    end

    include_examples 'handles event successfully'

    it 'sets subscription_status to paused' do
      operation.call
      organization.refresh!
      expect(organization.subscription_status).to eq('paused')
    end

    it 'retains stripe_subscription_id' do
      operation.call
      organization.refresh!
      expect(organization.stripe_subscription_id).to eq(stripe_subscription_id)
    end
  end

  context 'with unknown organization' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'paused',
        metadata: { 'custid' => 'unknown_custid' },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.paused', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(nil)
    end

    include_examples 'logs warning for missing organization'
  end
end

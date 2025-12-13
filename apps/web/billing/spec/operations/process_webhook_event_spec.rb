# apps/web/billing/spec/operations/process_webhook_event_spec.rb
#
# frozen_string_literal: true

# ProcessWebhookEvent Operation - Main Test Suite
#
# This file tests orchestration behavior: unhandled events, context options.
# Event-specific tests are in process_webhook_event/ subdirectory.
#
# Run all: pnpm run test:rspec apps/web/billing/spec/operations/
# Run this: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event_spec.rb

require_relative '../support/billing_spec_helper'
require_relative 'process_webhook_event/shared_examples'
require_relative '../../operations/process_webhook_event'

RSpec.describe Billing::Operations::ProcessWebhookEvent, :integration, :process_webhook_event do
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe '#call' do
    context 'unhandled event types' do
      let(:event) do
        build_stripe_event(
          type: 'customer.created',
          data_object: { id: 'cus_unknown', email: 'test@example.com' },
        )
      end
      let(:operation) { described_class.new(event: event) }

      include_examples 'ignores unhandled event'
    end

    context 'context options' do
      let(:test_email) { "ctx-#{SecureRandom.hex(4)}@example.com" }
      let(:stripe_subscription_id) { 'sub_ctx_456' }

      let!(:customer) { create_test_customer(custid: nil, email: test_email) }
      let!(:organization) do
        org = create_test_organization(customer: customer)
        org.stripe_subscription_id = stripe_subscription_id
        org.save
        org
      end

      let(:subscription) do
        build_stripe_subscription(
          id: stripe_subscription_id,
          customer: 'cus_ctx_123',
          status: 'active',
          metadata: { 'custid' => customer.custid },
        )
      end

      let(:event) { build_stripe_event(type: 'customer.subscription.updated', data_object: subscription) }

      before do
        allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
          .with(stripe_subscription_id)
          .and_return(organization)
      end

      it 'accepts replay context flag' do
        operation = described_class.new(event: event, context: { replay: true })
        expect(operation.call).to eq(:success)
      end

      it 'accepts skip_notifications context flag' do
        operation = described_class.new(event: event, context: { skip_notifications: true })
        expect(operation.call).to eq(:success)
      end

      it 'accepts worker source context' do
        operation = described_class.new(
          event: event,
          context: { source: :async_worker, source_message_id: 'msg_123', received_at: Time.now },
        )
        expect(operation.call).to eq(:success)
      end
    end
  end
end

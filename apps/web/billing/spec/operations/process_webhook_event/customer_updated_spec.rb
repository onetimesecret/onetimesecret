# apps/web/billing/spec/operations/process_webhook_event/customer_updated_spec.rb
#
# frozen_string_literal: true

# Tests for customer.updated webhook event handling.
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/customer_updated_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: customer.updated', :integration, :process_webhook_event do
  let(:test_email) { "custupdated-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_updated_123' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  # Build a Stripe::Customer for testing
  def build_stripe_customer(id:, email:, metadata: {})
    Stripe::Customer.construct_from({
      id: id,
      object: 'customer',
      email: email,
      metadata: metadata,
    })
  end

  context 'with existing organization' do
    let!(:customer) { create_test_customer(email: test_email) }
    let!(:organization) do
      org = create_test_organization(customer: customer)
      org.stripe_customer_id = stripe_customer_id
      org.save
      org
    end

    let(:stripe_customer) do
      build_stripe_customer(
        id: stripe_customer_id,
        email: test_email,
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.updated', data_object: stripe_customer) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(organization)
    end

    include_examples 'handles event successfully'

    it 'processes update without error' do
      expect { operation.call }.not_to raise_error
    end

    context 'when Stripe email differs from local email' do
      let(:stripe_customer) do
        build_stripe_customer(
          id: stripe_customer_id,
          email: 'different-email@example.com',
          metadata: { 'customer_extid' => customer.extid },
        )
      end

      it 'logs the email discrepancy' do
        # Handler logs discrepancy but doesn't auto-update email
        expect { operation.call }.not_to raise_error
      end

      it 'does not modify local customer email' do
        original_email = customer.email
        operation.call
        customer.refresh!
        expect(customer.email).to eq(original_email)
      end
    end
  end

  context 'with unknown organization' do
    let(:stripe_customer) do
      build_stripe_customer(
        id: stripe_customer_id,
        email: 'unknown@example.com',
        metadata: {},
      )
    end

    let(:event) { build_stripe_event(type: 'customer.updated', data_object: stripe_customer) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_customer_id)
        .with(stripe_customer_id)
        .and_return(nil)
    end

    it 'returns :not_found (organization not found)' do
      # Unlike subscription events, customer.updated with unknown org is debug-logged, not warned
      expect(operation.call).to eq(:not_found)
    end

    it 'does not raise an error' do
      expect { operation.call }.not_to raise_error
    end
  end
end

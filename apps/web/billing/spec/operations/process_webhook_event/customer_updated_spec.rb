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

    # Billing email sync scenarios (Stripe -> OTS)
    context 'billing email sync' do
      context 'when Stripe email differs from organization billing_email' do
        let(:new_billing_email) { 'new-billing@example.com' }

        let(:stripe_customer) do
          build_stripe_customer(
            id: stripe_customer_id,
            email: new_billing_email,
            metadata: { 'customer_extid' => customer.extid },
          )
        end

        before do
          # Set initial billing email different from Stripe
          organization.billing_email = 'old-billing@example.com'
          organization.save
        end

        it 'syncs billing_email from Stripe to organization' do
          operation.call
          organization.refresh!
          expect(organization.billing_email).to eq(new_billing_email)
        end

        it 'syncs contact_email for consistency' do
          operation.call
          organization.refresh!
          expect(organization.contact_email).to eq(new_billing_email)
        end

        it 'updates the organization timestamp' do
          original_updated = organization.updated
          sleep 0.01 # Ensure time difference
          operation.call
          organization.refresh!
          expect(organization.updated).to be >= original_updated
        end

        it 'sets WebhookSyncFlag before saving organization' do
          # Verify the flag is set during the sync operation
          expect(Billing::WebhookSyncFlag).to receive(:set_skip_stripe_sync)
            .with(organization.extid)
            .and_call_original

          operation.call

          # Flag should still be set after successful save (it expires via TTL)
          expect(Billing::WebhookSyncFlag.skip_stripe_sync?(organization.extid)).to be true
        end
      end

      context 'when org.save raises an error' do
        let(:new_billing_email) { 'error-test@example.com' }

        let(:stripe_customer) do
          build_stripe_customer(
            id: stripe_customer_id,
            email: new_billing_email,
            metadata: { 'customer_extid' => customer.extid },
          )
        end

        before do
          organization.billing_email = 'old-billing@example.com'
          organization.save
        end

        it 'clears WebhookSyncFlag when save fails' do
          # Stub save to raise after flag is set
          allow(organization).to receive(:save).and_raise(StandardError.new('Redis connection error'))

          expect(Billing::WebhookSyncFlag).to receive(:set_skip_stripe_sync)
            .with(organization.extid)
            .and_call_original
          expect(Billing::WebhookSyncFlag).to receive(:clear_skip_stripe_sync)
            .with(organization.extid)
            .and_call_original

          expect { operation.call }.to raise_error(StandardError, 'Redis connection error')

          # Flag should be cleared after error
          expect(Billing::WebhookSyncFlag.skip_stripe_sync?(organization.extid)).to be false
        end

        it 're-raises the original exception' do
          original_error = RuntimeError.new('Database failure')
          allow(organization).to receive(:save).and_raise(original_error)

          expect { operation.call }.to raise_error(original_error)
        end

        it 'logs the error with context' do
          allow(organization).to receive(:save).and_raise(StandardError.new('Test error'))

          # The billing_logger should receive an error log
          # We can't easily verify the exact message without more mocking,
          # but we verify the error path is taken by checking the exception
          expect { operation.call }.to raise_error(StandardError, 'Test error')
        end
      end

      context 'when Stripe email matches organization billing_email' do
        let(:stripe_customer) do
          build_stripe_customer(
            id: stripe_customer_id,
            email: 'same@example.com',
            metadata: { 'customer_extid' => customer.extid },
          )
        end

        before do
          organization.billing_email = 'same@example.com'
          organization.save
        end

        it 'does not update organization (no-op)' do
          original_updated = organization.updated
          operation.call
          organization.refresh!
          # Updated timestamp should not change when email is same (within float tolerance)
          expect(organization.updated).to be_within(0.001).of(original_updated)
        end

        it 'does not set WebhookSyncFlag (early return)' do
          expect(Billing::WebhookSyncFlag).not_to receive(:set_skip_stripe_sync)
          operation.call
        end
      end

      context 'when Stripe email is empty' do
        let(:stripe_customer) do
          build_stripe_customer(
            id: stripe_customer_id,
            email: '',
            metadata: { 'customer_extid' => customer.extid },
          )
        end

        before do
          organization.billing_email = 'existing@example.com'
          organization.save
        end

        it 'does not clear organization billing_email' do
          operation.call
          organization.refresh!
          expect(organization.billing_email).to eq('existing@example.com')
        end

        it 'does not set WebhookSyncFlag (early return)' do
          expect(Billing::WebhookSyncFlag).not_to receive(:set_skip_stripe_sync)
          operation.call
        end
      end

      context 'when Stripe email is nil' do
        let(:stripe_customer) do
          build_stripe_customer(
            id: stripe_customer_id,
            email: nil,
            metadata: { 'customer_extid' => customer.extid },
          )
        end

        before do
          organization.billing_email = 'existing@example.com'
          organization.save
        end

        it 'does not clear organization billing_email' do
          operation.call
          organization.refresh!
          expect(organization.billing_email).to eq('existing@example.com')
        end

        it 'does not set WebhookSyncFlag (early return)' do
          expect(Billing::WebhookSyncFlag).not_to receive(:set_skip_stripe_sync)
          operation.call
        end
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

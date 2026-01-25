# apps/web/billing/spec/operations/process_webhook_event/error_handling_spec.rb
#
# frozen_string_literal: true

# Tests for error handling in ProcessWebhookEvent operation.
#
# Covers:
# - Stripe API errors (retriable)
# - Missing customer/subscription (permanent failures)
# - Plan cache refresh errors (non-fatal)
#
# Run: pnpm run test:rspec apps/web/billing/spec/operations/process_webhook_event/error_handling_spec.rb

require_relative '../../support/billing_spec_helper'
require_relative 'shared_examples'
require_relative '../../../operations/process_webhook_event'

RSpec.describe 'ProcessWebhookEvent: error handling', :integration, :process_webhook_event do
  let(:test_email) { "error-#{SecureRandom.hex(4)}@example.com" }
  let(:stripe_customer_id) { 'cus_error_123' }
  let(:stripe_subscription_id) { 'sub_error_456' }

  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe 'Stripe API errors during checkout.session.completed' do
    let(:session) do
      build_stripe_session(
        id: 'cs_test_error',
        customer: stripe_customer_id,
        subscription: stripe_subscription_id,
      )
    end

    let(:event) { build_stripe_event(type: 'checkout.session.completed', data_object: session) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    context 'when Stripe::Subscription.retrieve raises API error' do
      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with(stripe_subscription_id)
          .and_raise(Stripe::APIError.new('API temporarily unavailable'))
      end

      it 'propagates the error for retry' do
        expect { operation.call }.to raise_error(Stripe::APIError)
      end
    end

    context 'when Stripe::Subscription.retrieve raises rate limit error' do
      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with(stripe_subscription_id)
          .and_raise(Stripe::RateLimitError.new('Too many requests'))
      end

      it 'propagates the error for retry' do
        expect { operation.call }.to raise_error(Stripe::RateLimitError)
      end
    end

    context 'when Stripe::Subscription.retrieve raises authentication error' do
      before do
        allow(Stripe::Subscription).to receive(:retrieve)
          .with(stripe_subscription_id)
          .and_raise(Stripe::AuthenticationError.new('Invalid API key'))
      end

      it 'propagates the error' do
        expect { operation.call }.to raise_error(Stripe::AuthenticationError)
      end
    end
  end

  describe 'missing customer in subscription metadata' do
    let!(:customer) { create_test_customer(email: test_email) }

    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: {}, # No customer_extid in metadata
      )
    end

    let(:session) do
      build_stripe_session(
        id: 'cs_test_missing',
        customer: stripe_customer_id,
        subscription: stripe_subscription_id,
      )
    end

    let(:event) { build_stripe_event(type: 'checkout.session.completed', data_object: session) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription)
    end

    it 'returns :skipped (missing customer_extid)' do
      # Missing customer_extid is logged as warning but doesn't fail
      expect(operation.call).to eq(:skipped)
    end

    it 'does not raise an error' do
      expect { operation.call }.not_to raise_error
    end
  end

  describe 'missing customer record' do
    let(:subscription) do
      build_stripe_subscription(
        id: stripe_subscription_id,
        customer: stripe_customer_id,
        status: 'active',
        metadata: { 'customer_extid' => 'urnonexistent00000000000000' },
      )
    end

    let(:session) do
      build_stripe_session(
        id: 'cs_test_no_customer',
        customer: stripe_customer_id,
        subscription: stripe_subscription_id,
      )
    end

    let(:event) { build_stripe_event(type: 'checkout.session.completed', data_object: session) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Stripe::Subscription).to receive(:retrieve)
        .with(stripe_subscription_id)
        .and_return(subscription)
    end

    it 'returns :not_found (customer not found)' do
      # Missing customer is logged as error but doesn't fail webhook
      expect(operation.call).to eq(:not_found)
    end

    it 'does not raise an error' do
      expect { operation.call }.not_to raise_error
    end
  end

  describe 'plan cache refresh errors' do
    let(:product) { build_stripe_product(id: 'prod_refresh_error') }
    let(:event) { build_stripe_event(type: 'product.updated', data_object: product) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    context 'when Billing::Plan.refresh_from_stripe raises error' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(StandardError.new('Cache refresh failed'))
      end

      it 'returns :success (cache errors are non-fatal)' do
        # Plan cache refresh errors are logged but don't fail the webhook
        expect(operation.call).to eq(:success)
      end

      it 'does not propagate the error' do
        expect { operation.call }.not_to raise_error
      end
    end

    context 'when Stripe API fails during refresh' do
      before do
        allow(Billing::Plan).to receive(:refresh_from_stripe)
          .and_raise(Stripe::APIError.new('Stripe unavailable'))
      end

      it 'returns :success (cache errors are non-fatal)' do
        expect(operation.call).to eq(:success)
      end

      it 'does not propagate the Stripe error' do
        expect { operation.call }.not_to raise_error
      end
    end
  end

  describe 'organization save errors' do
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
        status: 'paused',
        metadata: { 'customer_extid' => customer.extid },
      )
    end

    let(:event) { build_stripe_event(type: 'customer.subscription.paused', data_object: subscription) }
    let(:operation) { Billing::Operations::ProcessWebhookEvent.new(event: event) }

    before do
      allow(Onetime::Organization).to receive(:find_by_stripe_subscription_id)
        .with(stripe_subscription_id)
        .and_return(organization)
    end

    context 'when organization.save raises Redis error' do
      before do
        allow(organization).to receive(:save).and_raise(Redis::CannotConnectError.new('Connection refused'))
      end

      it 'propagates the error for retry' do
        expect { operation.call }.to raise_error(Redis::CannotConnectError)
      end
    end
  end
end

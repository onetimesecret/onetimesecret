# apps/web/billing/spec/controllers/webhooks_controller_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'
require_relative '../../plan_helpers'

RSpec.describe 'Billing::Controllers::Webhooks', :integration, :vcr, :stripe_sandbox_api do
  include Rack::Test::Methods

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:webhook_secret) { ENV.fetch('STRIPE_WEBHOOK_SECRET', 'whsec_test_secret') }
  let(:webhook_validator) { Billing::WebhookValidator.new }
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  after do
    # Clean up created test data
    created_organizations.each(&:destroy!)
    created_customers.each(&:destroy!)
  end

  describe 'POST /billing/webhook' do
    context 'security validation' do
      it 'rejects requests without signature header' do
        post '/billing/webhook', '{}', { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Missing signature header')
      end

      it 'rejects requests with invalid signature', :vcr do
        payload = {
          id: 'evt_test_invalid',
          type: 'customer.subscription.updated',
          data: { object: {} },
        }.to_json

        # Generate signature with wrong secret
        invalid_signature = generate_stripe_signature(
          payload: payload,
          secret: 'wrong_secret',
        )

        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => invalid_signature,
        }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid signature')
      end

      it 'rejects requests with expired timestamp', :vcr do
        payload = {
          id: 'evt_test_expired',
          type: 'customer.subscription.updated',
          data: { object: {} },
        }.to_json

        # Generate signature with timestamp older than tolerance (5 minutes)
        old_timestamp     = (Time.now - 600).to_i
        expired_signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: old_timestamp,
        )

        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => expired_signature,
        }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid event timestamp')
      end

      it 'rejects replay attacks (duplicate event_id)', :vcr do
        payload = {
          id: 'evt_test_replay',
          type: 'customer.subscription.updated',
          data: { object: { id: 'sub_test' } },
        }.to_json

        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
        )

        # First request should succeed
        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)

        # Second request with same event_id should be rejected as duplicate
        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('already processed')
      end

      it 'rejects malformed JSON payload' do
        invalid_payload = 'not valid json {'

        signature = generate_stripe_signature(
          payload: invalid_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', invalid_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(400)
        expect(last_response.body).to include('Invalid payload')
      end
    end

    context 'checkout.session.completed event' do
      let(:customer) do
        cust = Onetime::Customer.create!(email: "webhook-checkout-#{SecureRandom.hex(4)}@example.com")
        created_customers << cust
        cust
      end

      before do
        customer.save
      end

      it 'creates organization subscription from checkout session', :vcr do
        # Create a real Stripe customer and checkout session
        stripe_customer = Stripe::Customer.create(email: customer.email)

        subscription = Stripe::Subscription.create(
          customer: stripe_customer.id,
          items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
          metadata: {
            custid: customer.custid,
            plan_id: 'identity_v1',
            tier: 'single_team',
          },
        )

        event_payload = {
          id: "evt_checkout_#{SecureRandom.hex(8)}",
          type: 'checkout.session.completed',
          data: {
            object: {
              id: "cs_test_#{SecureRandom.hex(8)}",
              customer: stripe_customer.id,
              subscription: subscription.id,
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Event processed')

        # Verify organization was created/updated
        orgs = customer.organization_instances.to_a
        expect(orgs).not_to be_empty

        org = orgs.find { |o| o.is_default }
        expect(org).not_to be_nil
        expect(org.stripe_subscription_id).to eq(subscription.id)
        created_organizations.concat(orgs)
      end

      it 'handles missing customer gracefully', :vcr do
        event_payload = {
          id: "evt_missing_customer_#{SecureRandom.hex(8)}",
          type: 'checkout.session.completed',
          data: {
            object: {
              id: "cs_test_#{SecureRandom.hex(8)}",
              customer: 'cus_nonexistent',
              subscription: 'sub_test',
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        # Should still return 200 (logged but not critical error)
        expect(last_response.status).to eq(200)
      end
    end

    context 'customer.subscription.updated event' do
      let(:customer) do
        cust = Onetime::Customer.create!(email: "webhook-subupdate-#{SecureRandom.hex(4)}@example.com")
        created_customers << cust
        cust
      end

      let(:organization) do
        org = Onetime::Organization.create!('Test Org', customer, customer.email)
        created_organizations << org
        org
      end

      before do
        customer.save
        organization.save
      end

      it 'updates organization subscription status', :vcr do
        # Create real Stripe subscription
        stripe_customer = Stripe::Customer.create(email: customer.email)
        subscription    = Stripe::Subscription.create(
          customer: stripe_customer.id,
          items: [{ price: ENV.fetch('STRIPE_TEST_PRICE_ID', 'price_test') }],
        )

        # Associate subscription with organization
        organization.stripe_subscription_id = subscription.id
        organization.save

        # Update subscription status
        updated_subscription = Stripe::Subscription.update(
          subscription.id,
          metadata: { status: 'active' },
        )

        event_payload = {
          id: "evt_sub_updated_#{SecureRandom.hex(8)}",
          type: 'customer.subscription.updated',
          data: {
            object: updated_subscription.to_hash,
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)

        # Reload organization and verify update
        organization.reload
        expect(organization.subscription_status).to match(/active|trialing/)
      end
    end

    context 'customer.subscription.deleted event' do
      let(:customer) do
        cust = Onetime::Customer.create!(email: "webhook-subdelete-#{SecureRandom.hex(4)}@example.com")
        created_customers << cust
        cust
      end

      let(:organization) do
        org = Onetime::Organization.create!('Test Org', customer, customer.email)
        created_organizations << org
        org
      end

      before do
        customer.save
        organization.stripe_subscription_id = 'sub_test_deleted'
        organization.save
      end

      it 'clears organization billing fields', :vcr do
        event_payload = {
          id: "evt_sub_deleted_#{SecureRandom.hex(8)}",
          type: 'customer.subscription.deleted',
          data: {
            object: {
              id: organization.stripe_subscription_id,
              status: 'canceled',
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)

        # Verify billing fields cleared
        organization.reload
        expect(organization.stripe_subscription_id).to be_nil
      end
    end

    context 'product.updated and price.updated events' do
      it 'refreshes plan cache on product update', :vcr do
        event_payload = {
          id: "evt_product_updated_#{SecureRandom.hex(8)}",
          type: 'product.updated',
          data: {
            object: {
              id: 'prod_test',
              object: 'product',
              name: 'Updated Product',
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        expect(Billing::Plan).to receive(:refresh_from_stripe).and_call_original

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
      end

      it 'refreshes plan cache on price update', :vcr do
        event_payload = {
          id: "evt_price_updated_#{SecureRandom.hex(8)}",
          type: 'price.updated',
          data: {
            object: {
              id: 'price_test',
              object: 'price',
              unit_amount: 2999,
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
      end
    end

    context 'unhandled event types' do
      it 'returns success for unhandled event types', :vcr do
        event_payload = {
          id: "evt_unhandled_#{SecureRandom.hex(8)}",
          type: 'customer.created',
          data: {
            object: {
              id: 'cus_test',
              email: 'test@example.com',
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Event processed')
      end
    end

    context 'error handling and rollback' do
      it 'returns 500 and unmarks event on processing failure', :vcr do
        event_payload = {
          id: "evt_failure_#{SecureRandom.hex(8)}",
          type: 'checkout.session.completed',
          data: {
            object: {
              id: 'cs_test_failure',
              customer: 'cus_test',
              subscription: 'sub_test',
            },
          },
        }.to_json

        signature = generate_stripe_signature(
          payload: event_payload,
          secret: webhook_secret,
        )

        # Simulate processing failure
        allow_any_instance_of(Billing::Controllers::Webhooks)
          .to receive(:handle_checkout_completed)
          .and_raise(StandardError, 'Processing failed')

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('processing failed')

        # Verify event was unmarked for retry
        # Event should be processable again after failure
        allow_any_instance_of(Billing::Controllers::Webhooks)
          .to receive(:handle_checkout_completed)
          .and_call_original

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
      end
    end
  end
end

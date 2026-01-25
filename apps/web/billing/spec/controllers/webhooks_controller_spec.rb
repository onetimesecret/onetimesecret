# apps/web/billing/spec/controllers/webhooks_controller_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require 'rack/test'
require 'stripe'

# Load the billing application for controller testing
require_relative '../../application'
require_relative '../../plan_helpers'

RSpec.describe 'Billing::Controllers::Webhooks', :integration, :stripe_sandbox_api, :vcr do
  include Rack::Test::Methods

  # The Rack application for testing
  # Wrap with URLMap to match production mounting behavior
  def app
    @app ||= Rack::URLMap.new('/billing' => Billing::Application.new)
  end

  let(:webhook_secret) { 'whsec_test_secret' }
  let(:created_customers) { [] }
  let(:created_organizations) { [] }

  # Mock billing config struct
  let(:mock_billing_config) do
    Struct.new(:webhook_signing_secret, :publishable_key, :secret_key, keyword_init: true)
          .new(webhook_signing_secret: webhook_secret, publishable_key: 'pk_test', secret_key: 'sk_test')
  end

  before do
    # Mock billing config to provide webhook secret
    allow(Onetime).to receive(:billing_config).and_return(mock_billing_config)

    # Mock the Publisher to avoid requiring RabbitMQ in tests
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_billing_event).and_return(true)
  end

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
          object: 'event',
          created: Time.now.to_i,
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
          object: 'event',
          created: Time.now.to_i,
          type: 'customer.subscription.updated',
          data: { object: {} },
        }.to_json

        # Generate signature with timestamp older than tolerance (5 minutes)
        # Note: Stripe's library validates the timestamp in the signature header,
        # which results in SignatureVerificationError (not our custom timestamp check)
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
        # Stripe's library rejects old timestamps as invalid signature
        expect(last_response.body).to include('Invalid signature')
      end

      it 'rejects replay attacks (duplicate event_id)', :vcr do
        payload = {
          id: 'evt_test_replay',
          object: 'event',
          created: Time.now.to_i,
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
        expect(last_response.body).to include('already queued')
      end

      it 'stops retries after max retries reached', :vcr do
        event_id = "evt_max_retries_#{SecureRandom.hex(8)}"
        payload = {
          id: event_id,
          object: 'event',
          created: Time.now.to_i,
          type: 'customer.subscription.updated',
          data: { object: { id: 'sub_test' } },
        }.to_json

        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
        )

        # First request creates the event record
        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }
        expect(last_response.status).to eq(200)

        # Simulate max retries reached by updating the record directly
        event_record = Billing::StripeWebhookEvent.find_by_identifier(event_id)
        event_record.attempt_count = '3'
        event_record.processing_status = 'failed'
        event_record.error_message = 'Test error after max retries'
        event_record.save

        # Next request should return 200 but indicate max retries reached
        post '/billing/webhook', payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('max retries reached')
        # Should NOT have called enqueue again
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_billing_event).once
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

        # Malformed JSON should be rejected with 400
        # Note: Response body format may vary based on error handling middleware
        expect(last_response.status).to eq(400)
      end
    end

    context 'checkout.session.completed event' do
      it 'enqueues checkout session event for async processing', :vcr do
        event_payload = {
          id: "evt_checkout_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
          type: 'checkout.session.completed',
          data: {
            object: {
              id: "cs_test_#{SecureRandom.hex(8)}",
              customer: 'cus_test_123',
              subscription: 'sub_test_456',
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
        expect(last_response.body).to include('Event queued')
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_billing_event)
      end
    end

    context 'customer.subscription.updated event' do
      it 'enqueues subscription updated event for async processing', :vcr do
        event_payload = {
          id: "evt_sub_updated_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
          type: 'customer.subscription.updated',
          data: {
            object: {
              id: 'sub_test_123',
              status: 'active',
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
        expect(last_response.body).to include('Event queued')
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_billing_event)
      end
    end

    context 'customer.subscription.deleted event' do
      it 'enqueues subscription deleted event for async processing', :vcr do
        event_payload = {
          id: "evt_sub_deleted_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
          type: 'customer.subscription.deleted',
          data: {
            object: {
              id: 'sub_test_deleted',
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
        expect(last_response.body).to include('Event queued')
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_billing_event)
      end
    end

    context 'product.updated and price.updated events' do
      it 'enqueues product update event for async processing', :vcr do
        event_payload = {
          id: "evt_product_updated_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
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

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Event queued')
        expect(Onetime::Jobs::Publisher).to have_received(:enqueue_billing_event)
      end

      it 'enqueues price update event for async processing', :vcr do
        event_payload = {
          id: "evt_price_updated_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
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
        expect(last_response.body).to include('Event queued')
      end
    end

    context 'unhandled event types' do
      it 'enqueues unhandled event types for async processing', :vcr do
        event_payload = {
          id: "evt_unhandled_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
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

        # All valid events get queued, worker decides if it handles them
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Event queued')
      end
    end

    context 'error handling - queue unavailable' do
      it 'returns 500 when queue is unavailable', :vcr do
        # Simulate queue failure
        allow(Onetime::Jobs::Publisher).to receive(:enqueue_billing_event)
          .and_raise(Onetime::Problem, 'Queue unavailable')

        event_payload = {
          id: "evt_queue_failure_#{SecureRandom.hex(8)}",
          object: 'event',
          created: Time.now.to_i,
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

        post '/billing/webhook', event_payload, {
          'CONTENT_TYPE' => 'application/json',
          'HTTP_STRIPE_SIGNATURE' => signature,
        }

        expect(last_response.status).to eq(500)
        expect(last_response.body).to include('Queue unavailable')
      end
    end
  end
end

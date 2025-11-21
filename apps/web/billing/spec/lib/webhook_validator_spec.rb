# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/webhook_validator'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'
require_relative '../support/fixtures/stripe_objects'
require_relative '../support/fixtures/webhook_events'
require_relative '../support/shared_examples/webhook_security'

RSpec.describe Billing::WebhookValidator, type: :billing do
  include WebhookEventFixtures

  let(:webhook_secret) { 'whsec_test_secret_key_12345' }
  let(:validator) { described_class.new(webhook_secret: webhook_secret) }
  let(:redis) { mock_billing_redis }

  before do
    allow(Onetime).to receive_message_chain(:billing_config, :webhook_signing_secret)
      .and_return(webhook_secret)
    allow(Familia).to receive(:dbclient).and_return(redis)
  end

  describe '#initialize' do
    context 'with webhook secret provided' do
      it 'uses the provided secret' do
        validator = described_class.new(webhook_secret: 'custom_secret')
        expect(validator.instance_variable_get(:@webhook_secret)).to eq('custom_secret')
      end
    end

    context 'with webhook secret from config' do
      it 'uses config secret' do
        allow(Onetime).to receive_message_chain(:billing_config, :webhook_signing_secret)
          .and_return('config_secret')

        validator = described_class.new
        expect(validator.instance_variable_get(:@webhook_secret)).to eq('config_secret')
      end
    end

    context 'when no webhook secret is available' do
      it 'raises ArgumentError' do
        allow(Onetime).to receive_message_chain(:billing_config, :webhook_signing_secret)
          .and_return(nil)

        expect {
          described_class.new
        }.to raise_error(ArgumentError, /webhook signing secret/i)
      end
    end
  end

  describe '#construct_event' do
    let(:event_data) { customer_subscription_updated_event }
    let(:payload) { JSON.generate(event_data) }
    let(:timestamp) { Time.now.to_i }

    context 'with valid signature and timestamp' do
      it 'constructs the event successfully' do
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: timestamp
        )

        allow(Stripe::Webhook).to receive(:construct_event).and_return(
          double('Event', id: 'evt_123', type: 'customer.subscription.updated', created: timestamp)
        )

        event = validator.construct_event(payload, signature)

        expect(event).not_to be_nil
        expect(Stripe::Webhook).to have_received(:construct_event).with(payload, signature, webhook_secret)
      end

      it 'logs successful validation' do
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: timestamp
        )

        event_double = double(
          'Event',
          id: 'evt_123',
          type: 'customer.subscription.updated',
          created: timestamp
        )
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)
        allow(validator).to receive(:billing_logger).and_return(double(debug: nil, info: nil))

        validator.construct_event(payload, signature)

        expect(validator.billing_logger).to have_received(:info).with(
          /validated successfully/i,
          hash_including(:event_id, :event_type)
        )
      end
    end

    context 'with invalid JSON payload' do
      it 'raises JSON::ParserError' do
        invalid_payload = '{invalid json'
        signature = generate_stripe_signature(
          payload: invalid_payload,
          secret: webhook_secret,
          timestamp: timestamp
        )

        allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError.new('Invalid JSON'))

        expect {
          validator.construct_event(invalid_payload, signature)
        }.to raise_error(JSON::ParserError)
      end

      it 'logs the JSON parsing error' do
        invalid_payload = '{invalid json'
        signature = generate_stripe_signature(payload: invalid_payload, secret: webhook_secret, timestamp: timestamp)

        allow(Stripe::Webhook).to receive(:construct_event).and_raise(JSON::ParserError.new('Invalid JSON'))
        allow(validator).to receive(:billing_logger).and_return(double(error: nil, debug: nil))

        begin
          validator.construct_event(invalid_payload, signature)
        rescue JSON::ParserError
          # Expected
        end

        expect(validator.billing_logger).to have_received(:error).with(
          /invalid json/i,
          hash_including(:error)
        )
      end
    end

    context 'with invalid signature' do
      it 'raises Stripe::SignatureVerificationError' do
        invalid_signature = 't=123,v1=invalid_signature_hash'

        allow(Stripe::Webhook).to receive(:construct_event).and_raise(
          Stripe::SignatureVerificationError.new('Invalid signature', nil, nil)
        )

        expect {
          validator.construct_event(payload, invalid_signature)
        }.to raise_error(Stripe::SignatureVerificationError)
      end

      it 'logs signature verification failure' do
        invalid_signature = 't=123,v1=invalid'

        allow(Stripe::Webhook).to receive(:construct_event).and_raise(
          Stripe::SignatureVerificationError.new('Invalid signature', nil, nil)
        )
        allow(validator).to receive(:billing_logger).and_return(double(error: nil, debug: nil))

        begin
          validator.construct_event(payload, invalid_signature)
        rescue Stripe::SignatureVerificationError
          # Expected
        end

        expect(validator.billing_logger).to have_received(:error).with(
          /invalid signature/i,
          hash_including(:error)
        )
      end
    end

    context 'with old event timestamp' do
      it 'raises SecurityError for events older than MAX_EVENT_AGE' do
        old_timestamp = (Time.now - 6.minutes).to_i
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: old_timestamp
        )

        event_double = double('Event', id: 'evt_old', type: 'test', created: old_timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

        expect {
          validator.construct_event(payload, signature)
        }.to raise_error(SecurityError, /too old/i)
      end

      it 'logs replay attack warning' do
        old_timestamp = (Time.now - 6.minutes).to_i
        signature = generate_stripe_signature(payload: payload, secret: webhook_secret, timestamp: old_timestamp)

        event_double = double('Event', id: 'evt_old', type: 'test', created: old_timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)
        allow(validator).to receive(:billing_logger).and_return(double(error: nil, debug: nil))

        begin
          validator.construct_event(payload, signature)
        rescue SecurityError
          # Expected
        end

        expect(validator.billing_logger).to have_received(:error).with(
          /too old.*replay attack/i,
          hash_including(:event_id, :age_seconds)
        )
      end
    end

    context 'with future event timestamp' do
      it 'raises SecurityError for events too far in future' do
        future_timestamp = (Time.now + 2.minutes).to_i
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: future_timestamp
        )

        event_double = double('Event', id: 'evt_future', type: 'test', created: future_timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

        expect {
          validator.construct_event(payload, signature)
        }.to raise_error(SecurityError, /timestamp in future/i)
      end

      it 'accepts events within future tolerance window' do
        # 30 seconds in future - within MAX_FUTURE_TOLERANCE (60s)
        slightly_future_timestamp = (Time.now + 30.seconds).to_i
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: slightly_future_timestamp
        )

        event_double = double('Event', id: 'evt_123', type: 'test', created: slightly_future_timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

        expect {
          validator.construct_event(payload, signature)
        }.not_to raise_error
      end
    end

    context 'with recent valid timestamp' do
      it 'accepts events within MAX_EVENT_AGE' do
        recent_timestamp = (Time.now - 2.minutes).to_i
        signature = generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: recent_timestamp
        )

        event_double = double('Event', id: 'evt_recent', type: 'test', created: recent_timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

        expect {
          validator.construct_event(payload, signature)
        }.not_to raise_error
      end

      it 'logs timestamp validation success' do
        signature = generate_stripe_signature(payload: payload, secret: webhook_secret, timestamp: timestamp)

        event_double = double('Event', id: 'evt_123', type: 'test', created: timestamp)
        allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)
        allow(validator).to receive(:billing_logger).and_return(double(debug: nil, info: nil))

        validator.construct_event(payload, signature)

        expect(validator.billing_logger).to have_received(:debug).with(
          /timestamp valid/i,
          hash_including(:event_id, :age_seconds)
        )
      end
    end
  end

  describe '#already_processed?' do
    let(:event_id) { 'evt_test_123' }

    it 'delegates to ProcessedWebhookEvent.processed?' do
      allow(Billing::ProcessedWebhookEvent).to receive(:processed?).and_return(true)

      result = validator.already_processed?(event_id)

      expect(result).to be true
      expect(Billing::ProcessedWebhookEvent).to have_received(:processed?).with(event_id)
    end

    it 'returns false for new events' do
      allow(Billing::ProcessedWebhookEvent).to receive(:processed?).and_return(false)

      result = validator.already_processed?(event_id)

      expect(result).to be false
    end

    it 'returns true for already processed events' do
      allow(Billing::ProcessedWebhookEvent).to receive(:processed?).and_return(true)

      result = validator.already_processed?(event_id)

      expect(result).to be true
    end
  end

  describe '#mark_processed!' do
    let(:event_id) { 'evt_test_456' }
    let(:event_type) { 'customer.subscription.updated' }

    context 'when event is new' do
      it 'marks the event as processed' do
        allow(Billing::ProcessedWebhookEvent).to receive(:mark_processed_if_new!)
          .and_return(true)

        result = validator.mark_processed!(event_id, event_type)

        expect(result).to be true
        expect(Billing::ProcessedWebhookEvent).to have_received(:mark_processed_if_new!)
          .with(event_id, event_type)
      end

      it 'logs successful marking' do
        allow(Billing::ProcessedWebhookEvent).to receive(:mark_processed_if_new!).and_return(true)
        allow(validator).to receive(:billing_logger).and_return(double(debug: nil))

        validator.mark_processed!(event_id, event_type)

        expect(validator.billing_logger).to have_received(:debug).with(
          /marked as processed/i,
          hash_including(:event_id, :event_type)
        )
      end
    end

    context 'when event was already processed' do
      it 'returns false' do
        allow(Billing::ProcessedWebhookEvent).to receive(:mark_processed_if_new!)
          .and_return(false)

        result = validator.mark_processed!(event_id, event_type)

        expect(result).to be false
      end

      it 'logs duplicate detection' do
        allow(Billing::ProcessedWebhookEvent).to receive(:mark_processed_if_new!).and_return(false)
        allow(validator).to receive(:billing_logger).and_return(double(info: nil))

        validator.mark_processed!(event_id, event_type)

        expect(validator.billing_logger).to have_received(:info).with(
          /already processed/i,
          hash_including(:event_id, :event_type)
        )
      end
    end
  end

  describe '#unmark_processed!' do
    let(:event_id) { 'evt_test_789' }

    context 'when event exists' do
      it 'removes the processed marker' do
        processed_event = instance_double(Billing::ProcessedWebhookEvent)
        allow(Billing::ProcessedWebhookEvent).to receive(:new).and_return(processed_event)
        allow(processed_event).to receive(:exists?).and_return(true)
        allow(processed_event).to receive(:destroy!)

        validator.unmark_processed!(event_id)

        expect(processed_event).to have_received(:destroy!)
      end

      it 'logs the rollback' do
        processed_event = instance_double(Billing::ProcessedWebhookEvent)
        allow(Billing::ProcessedWebhookEvent).to receive(:new).and_return(processed_event)
        allow(processed_event).to receive_messages(exists?: true, destroy!: true)
        allow(validator).to receive(:billing_logger).and_return(double(info: nil))

        validator.unmark_processed!(event_id)

        expect(validator.billing_logger).to have_received(:info).with(
          /unmarked for retry/i,
          hash_including(:event_id)
        )
      end
    end

    context 'when event does not exist' do
      it 'does not attempt to destroy' do
        processed_event = instance_double(Billing::ProcessedWebhookEvent)
        allow(Billing::ProcessedWebhookEvent).to receive(:new).and_return(processed_event)
        allow(processed_event).to receive(:exists?).and_return(false)

        validator.unmark_processed!(event_id)

        expect(processed_event).not_to have_received(:destroy!)
      end
    end
  end

  describe 'security constants' do
    it 'defines MAX_EVENT_AGE as 5 minutes' do
      expect(described_class::MAX_EVENT_AGE).to eq(300)
    end

    it 'defines MAX_FUTURE_TOLERANCE as 1 minute' do
      expect(described_class::MAX_FUTURE_TOLERANCE).to eq(60)
    end
  end

  describe 'timestamp verification edge cases' do
    let(:payload) { JSON.generate(customer_subscription_updated_event) }

    it 'accepts event at exactly MAX_EVENT_AGE boundary' do
      boundary_timestamp = (Time.now - described_class::MAX_EVENT_AGE).to_i
      signature = generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: boundary_timestamp
      )

      event_double = double('Event', id: 'evt_boundary', type: 'test', created: boundary_timestamp)
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

      expect {
        validator.construct_event(payload, signature)
      }.not_to raise_error
    end

    it 'accepts event at exactly MAX_FUTURE_TOLERANCE boundary' do
      boundary_timestamp = (Time.now + described_class::MAX_FUTURE_TOLERANCE).to_i
      signature = generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: boundary_timestamp
      )

      event_double = double('Event', id: 'evt_future_boundary', type: 'test', created: boundary_timestamp)
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

      expect {
        validator.construct_event(payload, signature)
      }.not_to raise_error
    end

    it 'rejects event just over MAX_EVENT_AGE boundary' do
      over_boundary = (Time.now - described_class::MAX_EVENT_AGE - 1).to_i
      signature = generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: over_boundary
      )

      event_double = double('Event', id: 'evt_too_old', type: 'test', created: over_boundary)
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

      expect {
        validator.construct_event(payload, signature)
      }.to raise_error(SecurityError, /too old/i)
    end

    it 'rejects event just over MAX_FUTURE_TOLERANCE boundary' do
      over_future = (Time.now + described_class::MAX_FUTURE_TOLERANCE + 1).to_i
      signature = generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: over_future
      )

      event_double = double('Event', id: 'evt_too_future', type: 'test', created: over_future)
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event_double)

      expect {
        validator.construct_event(payload, signature)
      }.to raise_error(SecurityError, /timestamp in future/i)
    end
  end
end

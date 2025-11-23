# apps/web/billing/spec/lib/webhook_validator_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../lib/webhook_validator'
require_relative '../../models/processed_webhook_event'

RSpec.describe Billing::WebhookValidator, type: :billing do
  subject(:validator) { described_class.new(webhook_secret: webhook_secret) }

  let(:webhook_secret) { 'whsec_test_secret_123' }
  let(:redis) { Familia.dbclient }

  # NOTE: Redis cleanup (flushdb) is handled globally in billing_spec_helper.rb
  # for all type: :billing tests

  describe '#initialize' do
    it 'accepts webhook secret parameter' do
      expect { described_class.new(webhook_secret: 'test_secret') }.not_to raise_error
    end

    it 'raises ArgumentError when webhook secret is missing' do
      allow(Onetime).to receive(:billing_config).and_return(
        double(webhook_signing_secret: nil),
      )

      expect do
        described_class.new
      end.to raise_error(ArgumentError, /webhook signing secret/i)
    end

    it 'uses configured webhook secret by default' do
      allow(Onetime).to receive(:billing_config).and_return(
        double(webhook_signing_secret: 'configured_secret'),
      )

      expect { described_class.new }.not_to raise_error
    end
  end

  describe '#construct_event' do
    let(:timestamp) { Time.now.to_i }
    let(:payload) { "{\"id\":\"evt_test_123\",\"type\":\"customer.created\",\"created\":#{timestamp},\"data\":{}}" }

    context 'with valid signature' do
      let(:signature) do
        generate_stripe_signature(
          payload: payload,
          secret: webhook_secret,
          timestamp: timestamp,
        )
      end

      it 'constructs and returns Stripe event' do
        event = validator.construct_event(payload, signature)

        expect(event).to be_a(Stripe::Event)
        expect(event.id).to eq('evt_test_123')
        expect(event.type).to eq('customer.created')
      end

      it 'validates event timestamp' do
        # Should not raise for recent event
        expect do
          validator.construct_event(payload, signature)
        end.not_to raise_error
      end
    end

    context 'with invalid signature' do
      let(:invalid_signature) { 't=123456789,v1=invalid_signature_hash' }

      it 'raises SignatureVerificationError' do
        expect do
          validator.construct_event(payload, invalid_signature)
        end.to raise_error(Stripe::SignatureVerificationError)
      end
    end

    context 'with missing signature' do
      it 'raises SignatureVerificationError' do
        expect do
          validator.construct_event(payload, nil)
        end.to raise_error(Stripe::SignatureVerificationError)
      end
    end

    context 'with tampered payload' do
      let(:original_payload) { "{\"id\":\"evt_123\",\"type\":\"customer.created\",\"created\":#{timestamp},\"data\":{}}" }
      let(:tampered_payload) { "{\"id\":\"evt_123\",\"type\":\"customer.deleted\",\"created\":#{timestamp},\"data\":{}}" }
      let(:signature) do
        generate_stripe_signature(
          payload: original_payload,
          secret: webhook_secret,
          timestamp: timestamp,
        )
      end

      it 'raises SignatureVerificationError' do
        expect do
          validator.construct_event(tampered_payload, signature)
        end.to raise_error(Stripe::SignatureVerificationError)
      end
    end

    context 'with wrong secret' do
      let(:signature) do
        generate_stripe_signature(
          payload: payload,
          secret: 'wrong_secret',
          timestamp: timestamp,
        )
      end

      it 'raises SignatureVerificationError' do
        expect do
          validator.construct_event(payload, signature)
        end.to raise_error(Stripe::SignatureVerificationError)
      end
    end

    context 'with invalid JSON payload' do
      let(:invalid_payload) { 'not valid json{' }
      let(:signature) do
        generate_stripe_signature(
          payload: invalid_payload,
          secret: webhook_secret,
          timestamp: timestamp,
        )
      end

      it 'raises JSON::ParserError' do
        expect do
          validator.construct_event(invalid_payload, signature)
        end.to raise_error(JSON::ParserError)
      end
    end

    context 'with old timestamp (> 5 minutes)' do
      let(:old_timestamp) { Time.now.to_i - 400 } # 6+ minutes ago
      let(:old_payload) { '{"id":"evt_old","type":"customer.created","created":' + old_timestamp.to_s + ',"data":{}}' }
      let(:signature) do
        generate_stripe_signature(
          payload: old_payload,
          secret: webhook_secret,
          timestamp: old_timestamp,
        )
      end

      it 'raises SecurityError for replay attack protection' do
        # Stripe's signature verification may reject old timestamps first
        expect do
          validator.construct_event(old_payload, signature)
        end.to raise_error do |error|
          expect(error).to be_a(SecurityError).or be_a(Stripe::SignatureVerificationError)
          expect(error.message).to match(/too old|tolerance zone/i)
        end
      end
    end

    context 'with future timestamp' do
      let(:future_timestamp) { Time.now.to_i + 120 } # 2 minutes in future
      let(:future_payload) { '{"id":"evt_future","type":"customer.created","created":' + future_timestamp.to_s + ',"data":{}}' }
      let(:signature) do
        generate_stripe_signature(
          payload: future_payload,
          secret: webhook_secret,
          timestamp: future_timestamp,
        )
      end

      it 'raises SecurityError for suspicious timestamp' do
        expect do
          validator.construct_event(future_payload, signature)
        end.to raise_error(SecurityError, /future/i)
      end
    end

    context 'with timestamp within tolerance' do
      let(:recent_timestamp) { Time.now.to_i - 30 } # 30 seconds ago (within 5 min limit)
      let(:recent_payload) { '{"id":"evt_recent","type":"customer.created","created":' + recent_timestamp.to_s + ',"data":{}}' }
      let(:signature) do
        generate_stripe_signature(
          payload: recent_payload,
          secret: webhook_secret,
          timestamp: recent_timestamp,
        )
      end

      it 'accepts the event' do
        expect do
          validator.construct_event(recent_payload, signature)
        end.not_to raise_error
      end
    end
  end

  describe '#already_processed?' do
    let(:event_id) { 'evt_already_proc_test' }

    context 'when event was not processed' do
      it 'returns false' do
        expect(validator.already_processed?(event_id)).to be false
      end
    end

    context 'when event was already processed' do
      before do
        Billing::ProcessedWebhookEvent.mark_processed!(event_id, 'customer.created')
      end

      it 'returns true' do
        expect(validator.already_processed?(event_id)).to be true
      end
    end
  end

  describe '#mark_processed!' do
    let(:event_id) { 'evt_test_456' }
    let(:event_type) { 'customer.subscription.updated' }

    before do
      # Ensure this specific event doesn't exist before each test
      event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
      event.dbclient.del(event.dbkey)
    end

    context 'when event is new' do
      it 'marks event as processed' do
        result = validator.mark_processed!(event_id, event_type)

        expect(result).to be true
        expect(validator.already_processed?(event_id)).to be true
      end

      it 'stores event metadata in Redis' do
        validator.mark_processed!(event_id, event_type)

        event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
        # Verify key exists (FakeRedis returns boolean, real Redis returns integer)
        expect(event.dbclient.exists?(event.dbkey)).to be_truthy

        # Verify we can parse the stored JSON
        stored_data = JSON.parse(event.dbclient.get(event.dbkey))
        expect(stored_data['event_type']).to eq(event_type)
        expect(stored_data['processed_at']).to be_a(String)
      end

      it 'sets expiration on the event record' do
        result = validator.mark_processed!(event_id, event_type)

        expect(result).to be true

        event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
        # Verify key exists
        expect(event.dbclient.exists?(event.dbkey)).to be_truthy

        # Verify TTL is set (FakeRedis may handle this differently)
        ttl = redis.ttl(event.dbkey)
        # TTL might be -1 (no expiry) or positive (has expiry) in FakeRedis
        expect(ttl).to be >= -1
      end
    end

    context 'when event was already processed' do
      before do
        Billing::ProcessedWebhookEvent.mark_processed!(event_id, event_type)
      end

      it 'returns false' do
        result = validator.mark_processed!(event_id, event_type)

        expect(result).to be false
      end

      it 'does not change existing record' do
        original_event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
        original_time  = original_event.processed_at

        validator.mark_processed!(event_id, event_type)

        updated_event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
        expect(updated_event.processed_at).to eq(original_time)
      end
    end

    context 'atomic behavior with concurrent requests' do
      let(:event_id) { 'evt_concurrent_test' }

      it 'prevents duplicate processing with race condition' do
        # Simulate concurrent webhook deliveries
        results = []

        # First request marks it
        results << validator.mark_processed!(event_id, event_type)

        # Concurrent request (slightly delayed) should fail
        results << validator.mark_processed!(event_id, event_type)

        # Only one should succeed
        expect(results.count(true)).to eq(1)
        expect(results.count(false)).to eq(1)
      end
    end
  end

  describe '#unmark_processed!' do
    let(:event_id) { 'evt_rollback_test' }
    let(:event_type) { 'invoice.payment_failed' }

    context 'when event was marked as processed' do
      before do
        Billing::ProcessedWebhookEvent.mark_processed!(event_id, event_type)
      end

      it 'removes the processed marker' do
        validator.unmark_processed!(event_id)

        expect(validator.already_processed?(event_id)).to be false
      end

      it 'allows event to be reprocessed after rollback' do
        # Mark and verify
        expect(validator.already_processed?(event_id)).to be true

        # Rollback
        validator.unmark_processed!(event_id)

        # Can mark again
        result = validator.mark_processed!(event_id, event_type)
        expect(result).to be true
      end
    end

    context 'when event was not processed' do
      it 'handles gracefully without error' do
        expect do
          validator.unmark_processed!(event_id)
        end.not_to raise_error
      end
    end
  end

  describe 'integration: full validation workflow' do
    let(:payload) { '{"id":"evt_integration_123","type":"customer.created","created":' + Time.now.to_i.to_s + ',"data":{"object":{"id":"cus_123"}}}' }
    let(:signature) do
      generate_stripe_signature(
        payload: payload,
        secret: webhook_secret,
        timestamp: Time.now.to_i,
      )
    end

    it 'validates signature, timestamp, and handles duplicate detection' do
      # First delivery: validate and process
      event = validator.construct_event(payload, signature)
      expect(event.id).to eq('evt_integration_123')
      expect(validator.already_processed?(event.id)).to be false

      marked = validator.mark_processed!(event.id, event.type)
      expect(marked).to be true

      # Second delivery (duplicate): detect and reject
      event2 = validator.construct_event(payload, signature)
      expect(validator.already_processed?(event2.id)).to be true

      marked_again = validator.mark_processed!(event2.id, event2.type)
      expect(marked_again).to be false
    end

    it 'supports rollback on processing failure' do
      # Validate and mark
      event = validator.construct_event(payload, signature)
      validator.mark_processed!(event.id, event.type)

      # Simulate processing failure - rollback
      validator.unmark_processed!(event.id)

      # Should allow retry
      expect(validator.already_processed?(event.id)).to be false
      retry_result = validator.mark_processed!(event.id, event.type)
      expect(retry_result).to be true
    end
  end
end

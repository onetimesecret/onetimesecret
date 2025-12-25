# apps/web/billing/spec/lib/webhook_validator_spec.rb
#
# frozen_string_literal: true

require_relative '../support/billing_spec_helper'
require_relative '../../lib/webhook_validator'
require_relative '../../models/stripe_webhook_event'

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

  describe '#initialize_event_record' do
    let(:timestamp) { Time.now.to_i }
    let(:payload) do
      {
        id: 'evt_metadata_test',
        object: 'event',
        type: 'customer.subscription.updated',
        api_version: '2023-10-16',
        created: timestamp,
        livemode: false,
        pending_webhooks: 1,
        request: { id: 'req_test123' },
        data: {
          object: { id: 'sub_test123', object: 'subscription' },
        },
      }.to_json
    end
    let(:stripe_event) { Stripe::Event.construct_from(JSON.parse(payload)) }

    it 'initializes event with full Stripe metadata' do
      event = validator.initialize_event_record(stripe_event, payload)

      expect(event.stripe_event_id).to eq('evt_metadata_test')
      expect(event.event_type).to eq('customer.subscription.updated')
      expect(event.api_version).to eq('2023-10-16')
      expect(event.livemode).to eq('false')
      expect(event.created).to eq(timestamp.to_s)
      expect(event.request_id).to eq('req_test123')
      expect(event.data_object_id).to eq('sub_test123')
      expect(event.pending_webhooks).to eq('1')
      expect(event.event_payload).to eq(payload)
      expect(event.first_seen_at).not_to be_nil
      expect(event.attempt_count).to eq('0')
    end

    it 'stores event payload for replay' do
      event = validator.initialize_event_record(stripe_event, payload)

      expect(event.event_payload).to eq(payload)
      expect(event.deserialize_payload).to be_a(Hash)
      expect(event.deserialize_payload['id']).to eq('evt_metadata_test')
    end

    it 'only initializes once for the same event' do
      # First call
      event1     = validator.initialize_event_record(stripe_event, payload)
      first_seen = event1.first_seen_at

      # Second call - should return existing data
      event2 = validator.initialize_event_record(stripe_event, payload)
      expect(event2.first_seen_at).to eq(first_seen)
    end

    it 'persists metadata to Redis' do
      validator.initialize_event_record(stripe_event, payload)

      # Load fresh from Redis
      reloaded = Billing::StripeWebhookEvent.find_by_identifier('evt_metadata_test')
      expect(reloaded).not_to be_nil
      expect(reloaded.api_version).to eq('2023-10-16')
      expect(reloaded.data_object_id).to eq('sub_test123')
      expect(reloaded.event_payload).to eq(payload)
    end
  end
end

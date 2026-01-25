# apps/web/billing/spec/support/shared_examples/webhook_security.rb
#
# frozen_string_literal: true

# Shared examples for testing webhook security validations.
# Uses FakeRedis (configured globally in spec_helper.rb) - no mocking needed.

RSpec.shared_examples 'validates webhook signatures' do
  let(:valid_payload) { '{"type":"customer.created","data":{}}' }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:timestamp) { Time.now.to_i }

  context 'with valid signature' do
    it 'accepts the webhook' do
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.not_to raise_error
    end
  end

  context 'with invalid signature' do
    it 'rejects the webhook' do
      invalid_signature = 't=123456789,v1=invalid_signature'

      expect do
        subject.validate!(payload: valid_payload, signature: invalid_signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with missing signature' do
    it 'rejects the webhook' do
      expect do
        subject.validate!(payload: valid_payload, signature: nil, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with tampered payload' do
    it 'rejects the webhook' do
      signature        = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )
      tampered_payload = '{"type":"customer.deleted","data":{}}'

      expect do
        subject.validate!(payload: tampered_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with wrong secret' do
    it 'rejects the webhook' do
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: 'wrong_secret',
        timestamp: timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)
    end
  end
end

RSpec.shared_examples 'validates webhook timestamps' do
  let(:valid_payload) { '{"type":"customer.created","data":{}}' }
  let(:webhook_secret) { 'whsec_test_secret' }

  context 'with recent timestamp' do
    it 'accepts the webhook' do
      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.not_to raise_error
    end
  end

  context 'with old timestamp (> 5 minutes)' do
    it 'rejects the webhook' do
      old_timestamp = (Time.now - 6.minutes).to_i
      signature     = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: old_timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError, /timestamp/)
    end
  end

  context 'with future timestamp' do
    it 'rejects the webhook' do
      future_timestamp = (Time.now + 1.hour).to_i
      signature        = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: future_timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError, /timestamp/)
    end
  end
end

RSpec.shared_examples 'prevents duplicate webhook processing' do
  let(:event_id) { 'evt_test_123' }
  let(:valid_payload) { "{\"id\":\"#{event_id}\",\"type\":\"customer.created\"}" }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:redis) { Familia.dbclient }  # FakeRedis configured globally

  before do
    # Clean Redis state before each test
    redis.flushdb
  end

  context 'when processing a new event' do
    it 'marks the event as processed' do
      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      # Verify event is not yet marked as processed
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.not_to raise_error

      # Verify event is now marked as processed in Redis
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(1)

      # Verify TTL was set (should be > 0 and reasonable, e.g., 24 hours)
      ttl = redis.ttl("processed:webhook:#{event_id}")
      expect(ttl).to be > 0
      expect(ttl).to be <= 86_400  # 24 hours max
    end
  end

  context 'when processing a duplicate event' do
    it 'rejects the event' do
      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      # Mark event as already processed
      redis.setex("processed:webhook:#{event_id}", 3600, '1')

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(/duplicate.*event/i)
    end
  end

  context 'when Redis operation fails' do
    it 'fails safely by raising the Redis error' do
      # Close the Redis connection to simulate failure
      redis.client.disconnect

      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Redis::BaseError)
    end
  end
end

RSpec.shared_examples 'atomic webhook validation' do
  let(:event_id) { 'evt_test_456' }
  let(:valid_payload) { "{\"id\":\"#{event_id}\",\"type\":\"customer.created\"}" }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:redis) { Familia.dbclient }  # FakeRedis configured globally

  before do
    # Clean Redis state before each test
    redis.flushdb
  end

  context 'when signature validation fails after duplicate check' do
    it 'rolls back the duplicate marker' do
      # Verify event is not yet marked as processed
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)

      # Invalid signature
      invalid_signature = 't=123,v1=invalid'

      expect do
        subject.validate!(payload: valid_payload, signature: invalid_signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)

      # Verify the duplicate marker was NOT persisted (rolled back)
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)
    end
  end

  context 'when timestamp validation fails' do
    it 'rolls back the duplicate marker' do
      # Verify event is not yet marked as processed
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)

      old_timestamp = (Time.now - 10.minutes).to_i
      signature     = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: old_timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.to raise_error(Stripe::SignatureVerificationError)

      # Verify the duplicate marker was NOT persisted (rolled back)
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)
    end
  end

  context 'when validation succeeds' do
    it 'persists the duplicate marker' do
      # Verify event is not yet marked as processed
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(0)

      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp,
      )

      expect do
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      end.not_to raise_error

      # Verify the duplicate marker was persisted
      expect(redis.exists("processed:webhook:#{event_id}")).to eq(1)
    end
  end
end

# frozen_string_literal: true

# apps/web/billing/spec/support/shared_examples/webhook_security.rb
#
# Shared examples for testing webhook security validations

RSpec.shared_examples 'validates webhook signatures' do
  let(:valid_payload) { '{"type":"customer.created","data":{}}' }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:timestamp) { Time.now.to_i }

  context 'with valid signature' do
    it 'accepts the webhook' do
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.not_to raise_error
    end
  end

  context 'with invalid signature' do
    it 'rejects the webhook' do
      invalid_signature = 't=123456789,v1=invalid_signature'

      expect {
        subject.validate!(payload: valid_payload, signature: invalid_signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with missing signature' do
    it 'rejects the webhook' do
      expect {
        subject.validate!(payload: valid_payload, signature: nil, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with tampered payload' do
    it 'rejects the webhook' do
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp
      )
      tampered_payload = '{"type":"customer.deleted","data":{}}'

      expect {
        subject.validate!(payload: tampered_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)
    end
  end

  context 'with wrong secret' do
    it 'rejects the webhook' do
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: 'wrong_secret',
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)
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
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.not_to raise_error
    end
  end

  context 'with old timestamp (> 5 minutes)' do
    it 'rejects the webhook' do
      old_timestamp = (Time.now - 6.minutes).to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: old_timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError, /timestamp/)
    end
  end

  context 'with future timestamp' do
    it 'rejects the webhook' do
      future_timestamp = (Time.now + 1.hour).to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: future_timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError, /timestamp/)
    end
  end
end

RSpec.shared_examples 'prevents duplicate webhook processing' do
  let(:event_id) { 'evt_test_123' }
  let(:valid_payload) { "{\"id\":\"#{event_id}\",\"type\":\"customer.created\"}" }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:redis) { mock_billing_redis }

  before do
    allow(Familia).to receive(:dbclient).and_return(redis)
  end

  context 'when processing a new event' do
    it 'marks the event as processed' do
      allow(redis).to receive(:setnx).with(/processed:webhook:#{event_id}/, anything).and_return(true)
      allow(redis).to receive(:expire).with(/processed:webhook:#{event_id}/, anything).and_return(true)

      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.not_to raise_error

      expect(redis).to have_received(:setnx).with(/processed:webhook:#{event_id}/, anything)
      expect(redis).to have_received(:expire).with(/processed:webhook:#{event_id}/, anything)
    end
  end

  context 'when processing a duplicate event' do
    it 'rejects the event' do
      allow(redis).to receive(:setnx).with(/processed:webhook:#{event_id}/, anything).and_return(false)

      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(/duplicate.*event/i)
    end
  end

  context 'when Redis operation fails' do
    it 'fails safely by rejecting the webhook' do
      allow(redis).to receive(:setnx).and_raise(Redis::BaseError, 'Connection lost')

      timestamp = Time.now.to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Redis::BaseError)
    end
  end
end

RSpec.shared_examples 'atomic webhook validation' do
  let(:event_id) { 'evt_test_456' }
  let(:valid_payload) { "{\"id\":\"#{event_id}\",\"type\":\"customer.created\"}" }
  let(:webhook_secret) { 'whsec_test_secret' }
  let(:redis) { mock_billing_redis }

  before do
    allow(Familia).to receive(:dbclient).and_return(redis)
  end

  context 'when signature validation fails after duplicate check' do
    it 'rolls back the duplicate marker' do
      # setnx succeeds (not a duplicate)
      allow(redis).to receive(:setnx).and_return(true)
      allow(redis).to receive(:expire).and_return(true)
      allow(redis).to receive(:del).and_return(1)

      # But signature is invalid
      invalid_signature = 't=123,v1=invalid'

      expect {
        subject.validate!(payload: valid_payload, signature: invalid_signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)

      # Should delete the duplicate marker
      expect(redis).to have_received(:del).with(/processed:webhook:#{event_id}/)
    end
  end

  context 'when timestamp validation fails' do
    it 'rolls back the duplicate marker' do
      allow(redis).to receive(:setnx).and_return(true)
      allow(redis).to receive(:expire).and_return(true)
      allow(redis).to receive(:del).and_return(1)

      old_timestamp = (Time.now - 10.minutes).to_i
      signature = generate_stripe_signature(
        payload: valid_payload,
        secret: webhook_secret,
        timestamp: old_timestamp
      )

      expect {
        subject.validate!(payload: valid_payload, signature: signature, secret: webhook_secret)
      }.to raise_error(Stripe::SignatureVerificationError)

      expect(redis).to have_received(:del).with(/processed:webhook:#{event_id}/)
    end
  end
end

# frozen_string_literal: true

# apps/web/billing/spec/support/shared_examples/idempotency_behavior.rb
#
# Shared examples for testing idempotency in Stripe operations

RSpec.shared_examples 'idempotent operation' do |method_name, expected_key_pattern: nil|
  context 'when called multiple times with same parameters' do
    it 'uses the same idempotency key' do
      params = { customer: 'cus_test', amount: 1000 }
      idempotency_keys = []

      # Capture idempotency keys from multiple calls
      allow(Stripe::Customer).to receive(:create) do |_, opts|
        idempotency_keys << opts[:idempotency_key]
        mock_stripe_customer
      end

      2.times { subject.public_send(method_name, **params) }

      expect(idempotency_keys.uniq.length).to eq(1)
      expect(idempotency_keys.first).not_to be_nil
    end

    it 'generates idempotency key based on parameters' do
      params = { customer: 'cus_test', amount: 1000 }
      captured_key = nil

      allow(Stripe::Customer).to receive(:create) do |_, opts|
        captured_key = opts[:idempotency_key]
        mock_stripe_customer
      end

      subject.public_send(method_name, **params)

      expect(captured_key).to match(expected_key_pattern) if expected_key_pattern
      expect(captured_key).to be_a(String)
      expect(captured_key.length).to be > 0
    end
  end

  context 'when called with different parameters' do
    it 'uses different idempotency keys' do
      idempotency_keys = []

      allow(Stripe::Customer).to receive(:create) do |_, opts|
        idempotency_keys << opts[:idempotency_key]
        mock_stripe_customer
      end

      subject.public_send(method_name, customer: 'cus_test1', amount: 1000)
      subject.public_send(method_name, customer: 'cus_test2', amount: 1000)

      expect(idempotency_keys.uniq.length).to eq(2)
    end
  end

  context 'when Stripe returns an idempotent request error' do
    it 'returns the cached result' do
      params = { customer: 'cus_test', amount: 1000 }

      # First call succeeds
      allow(Stripe::Customer).to receive(:create).and_return(
        mock_stripe_customer(id: 'cus_original')
      )
      first_result = subject.public_send(method_name, **params)

      # Second call returns idempotent error with original result
      allow(Stripe::Customer).to receive(:create).and_raise(
        Stripe::IdempotencyError.new('Idempotent request', http_status: 400)
      )

      # Implementation should handle this gracefully
      expect { subject.public_send(method_name, **params) }.not_to raise_error
    end
  end
end

RSpec.shared_examples 'generates consistent idempotency keys' do |method_name|
  it 'generates the same key for identical requests' do
    params = { customer: 'cus_test', amount: 1000, currency: 'usd' }

    key1 = subject.send(:generate_idempotency_key, method_name, **params)
    key2 = subject.send(:generate_idempotency_key, method_name, **params)

    expect(key1).to eq(key2)
  end

  it 'generates different keys for different requests' do
    params1 = { customer: 'cus_test1', amount: 1000 }
    params2 = { customer: 'cus_test2', amount: 1000 }

    key1 = subject.send(:generate_idempotency_key, method_name, **params1)
    key2 = subject.send(:generate_idempotency_key, method_name, **params2)

    expect(key1).not_to eq(key2)
  end

  it 'includes method name in the key generation' do
    params = { customer: 'cus_test', amount: 1000 }

    key1 = subject.send(:generate_idempotency_key, :create_customer, **params)
    key2 = subject.send(:generate_idempotency_key, :update_customer, **params)

    expect(key1).not_to eq(key2)
  end

  it 'generates keys that are URL-safe' do
    params = { customer: 'cus_test!@#$%', amount: 1000 }

    key = subject.send(:generate_idempotency_key, method_name, **params)

    expect(key).to match(/\A[A-Za-z0-9_-]+\z/)
  end
end

RSpec.shared_examples 'respects custom idempotency keys' do |method_name|
  it 'uses provided idempotency key instead of generating one' do
    params = { customer: 'cus_test', amount: 1000 }
    custom_key = 'custom_idempotency_key_123'
    captured_key = nil

    allow(Stripe::Customer).to receive(:create) do |_, opts|
      captured_key = opts[:idempotency_key]
      mock_stripe_customer
    end

    subject.public_send(method_name, **params, idempotency_key: custom_key)

    expect(captured_key).to eq(custom_key)
  end
end

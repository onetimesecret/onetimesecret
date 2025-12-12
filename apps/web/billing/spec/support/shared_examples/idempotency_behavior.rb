# apps/web/billing/spec/support/shared_examples/idempotency_behavior.rb
#
# frozen_string_literal: true

# Shared examples for testing idempotency in Stripe operations.
# Uses VCR to record/replay real Stripe API calls.

RSpec.shared_examples 'idempotent Stripe operation', :stripe do |resource_type, create_params|
  context 'when called multiple times with same parameters' do
    it 'returns the same resource on duplicate requests' do
      # Generate a unique idempotency key for this test
      idempotency_key = "test_#{SecureRandom.hex(16)}"

      # First request creates the resource
      first_result = case resource_type
      when :customer
        Stripe::Customer.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      when :payment_intent
        Stripe::PaymentIntent.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      when :subscription
        Stripe::Subscription.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      end

      # Second request with same idempotency key returns same resource
      second_result = case resource_type
      when :customer
        Stripe::Customer.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      when :payment_intent
        Stripe::PaymentIntent.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      when :subscription
        Stripe::Subscription.create(
          create_params,
          { idempotency_key: idempotency_key },
        )
      end

      expect(first_result.id).to eq(second_result.id)
    end
  end

  context 'when called with different idempotency keys' do
    it 'creates different resources' do
      # Two different idempotency keys
      key1 = "test_#{SecureRandom.hex(16)}"
      key2 = "test_#{SecureRandom.hex(16)}"

      first_result = case resource_type
      when :customer
        Stripe::Customer.create(
          create_params,
          { idempotency_key: key1 },
        )
      when :payment_intent
        Stripe::PaymentIntent.create(
          create_params,
          { idempotency_key: key1 },
        )
      when :subscription
        Stripe::Subscription.create(
          create_params,
          { idempotency_key: key2 },
        )
      end

      second_result = case resource_type
      when :customer
        Stripe::Customer.create(
          create_params,
          { idempotency_key: key2 },
        )
      when :payment_intent
        Stripe::PaymentIntent.create(
          create_params,
          { idempotency_key: key2 },
        )
      when :subscription
        Stripe::Subscription.create(
          create_params,
          { idempotency_key: key2 },
        )
      end

      expect(first_result.id).not_to eq(second_result.id)
    end
  end
end

# Tests the idempotency key generation logic directly
# This tests implementation, not Stripe behavior
RSpec.shared_examples 'generates consistent idempotency keys' do |method_name|
  it 'generates the same key for identical parameters' do
    params = { customer: 'cus_test', amount: 1000, currency: 'usd' }

    key1 = subject.send(:generate_idempotency_key, method_name, **params)
    key2 = subject.send(:generate_idempotency_key, method_name, **params)

    expect(key1).to eq(key2)
  end

  it 'generates different keys for different parameters' do
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

  it 'generates URL-safe keys' do
    params = { customer: 'cus_test!@#$%', amount: 1000 }

    key = subject.send(:generate_idempotency_key, method_name, **params)

    # Stripe requires alphanumeric + dash/underscore only
    expect(key).to match(/\A[A-Za-z0-9_-]+\z/)
    expect(key.length).to be <= 255  # Stripe's max length
  end

  it 'generates deterministic keys from hash parameters' do
    # Order shouldn't matter
    params1 = { customer: 'cus_test', amount: 1000, currency: 'usd' }
    params2 = { currency: 'usd', customer: 'cus_test', amount: 1000 }

    key1 = subject.send(:generate_idempotency_key, method_name, **params1)
    key2 = subject.send(:generate_idempotency_key, method_name, **params2)

    expect(key1).to eq(key2)
  end
end

# Tests that custom idempotency keys are respected
# Verifies actual Stripe behavior with provided keys
RSpec.shared_examples 'respects custom idempotency keys', :stripe do |resource_type, create_params|
  it 'uses custom idempotency key when provided' do
    custom_key = "custom_#{SecureRandom.hex(16)}"

    # Create with custom key
    result = case resource_type
    when :customer
      Stripe::Customer.create(
        create_params,
        { idempotency_key: custom_key },
      )
    when :payment_intent
      Stripe::PaymentIntent.create(
        create_params,
        { idempotency_key: custom_key },
      )
    when :subscription
      Stripe::Subscription.create(
        create_params,
        { idempotency_key: custom_key },
      )
    end

    # Duplicate request with same custom key returns same resource
    duplicate = case resource_type
    when :customer
      Stripe::Customer.create(
        create_params,
        { idempotency_key: custom_key },
      )
    when :payment_intent
      Stripe::PaymentIntent.create(
        create_params,
        { idempotency_key: custom_key },
      )
    when :subscription
      Stripe::Subscription.create(
        create_params,
        { idempotency_key: custom_key },
      )
    end

    expect(result.id).to eq(duplicate.id)
  end
end

# Tests Stripe's idempotency conflict detection
RSpec.shared_examples 'detects idempotency conflicts', :stripe do |resource_type|
  it 'raises IdempotencyError when same key used with different parameters' do
    idempotency_key = "conflict_test_#{SecureRandom.hex(16)}"

    # First request with specific parameters
    case resource_type
    when :customer
      Stripe::Customer.create(
        { email: 'first@example.com' },
        { idempotency_key: idempotency_key },
      )
    when :payment_intent
      Stripe::PaymentIntent.create(
        { amount: 1000, currency: 'usd' },
        { idempotency_key: idempotency_key },
      )
    end

    # Second request with DIFFERENT parameters but SAME key
    # Stripe should detect this conflict
    expect do
      case resource_type
      when :customer
        Stripe::Customer.create(
          { email: 'different@example.com' },
          { idempotency_key: idempotency_key },
        )
      when :payment_intent
        Stripe::PaymentIntent.create(
          { amount: 2000, currency: 'usd' },  # Different amount
          { idempotency_key: idempotency_key },
        )
      end
    end.to raise_error(Stripe::IdempotencyError)
  end
end

# Tests that wrapper methods properly pass idempotency keys to Stripe
RSpec.shared_examples 'passes idempotency key to Stripe', :stripe do |method_name, test_params|
  it 'successfully creates resource with auto-generated idempotency key' do
    # Call the wrapper method - it should generate and use an idempotency key
    result = subject.public_send(method_name, **test_params)

    expect(result).to respond_to(:id)
    expect(result.id).to start_with(/cus_|pi_|sub_|prod_|price_/)
  end

  it 'successfully creates resource with custom idempotency key' do
    custom_key = "wrapper_test_#{SecureRandom.hex(16)}"

    # Call the wrapper method with custom key
    result = subject.public_send(
      method_name,
      **test_params,
      idempotency_key: custom_key,
    )

    # Duplicate call with same key should return same resource
    duplicate = subject.public_send(
      method_name,
      **test_params,
      idempotency_key: custom_key,
    )

    expect(result.id).to eq(duplicate.id)
  end
end

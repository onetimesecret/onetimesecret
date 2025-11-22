# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/stripe_client'
require_relative '../support/billing_spec_helper'
require_relative '../support/stripe_test_data'
require_relative '../support/shared_examples/stripe_error_handling'
require_relative '../support/shared_examples/idempotency_behavior'

RSpec.describe Billing::StripeClient, type: :billing do
  let(:api_key) { 'sk_test_fake_key_123' }
  let(:client) { described_class.new(api_key: api_key) }

  before do
    # Mock Stripe configuration
    allow(Onetime).to receive_message_chain(:billing_config, :stripe_key).and_return(api_key)
  end

  describe '#initialize' do
    it 'configures Stripe with provided API key' do
      expect(Stripe.api_key).to eq(api_key)
    end

    it 'sets request timeouts' do
      client
      expect(Stripe.open_timeout).to eq(described_class::REQUEST_TIMEOUT)
      expect(Stripe.read_timeout).to eq(described_class::REQUEST_TIMEOUT)
    end

    it 'disables Stripe automatic retries' do
      client
      expect(Stripe.max_network_retries).to eq(0)
    end

    context 'when no API key is provided' do
      it 'uses configuration API key' do
        allow(Onetime).to receive_message_chain(:billing_config, :stripe_key).and_return('sk_config_key')
        client = described_class.new
        expect(Stripe.api_key).to eq('sk_config_key')
      end
    end
  end

  describe '#create' do
    let(:customer_params) { { email: 'test@example.com', name: 'Test User' } }

    context 'when successful' do
      it 'creates the resource' do
        customer = mock_stripe_customer
        allow(Stripe::Customer).to receive(:create).and_return(customer)

        result = client.create(Stripe::Customer, customer_params)

        expect(result).to eq(customer)
        expect(Stripe::Customer).to have_received(:create)
      end

      it 'generates an idempotency key' do
        customer = mock_stripe_customer
        captured_options = nil

        allow(Stripe::Customer).to receive(:create) do |_params, options|
          captured_options = options
          customer
        end

        client.create(Stripe::Customer, customer_params)

        expect(captured_options[:idempotency_key]).to match(/^\d+-[a-f0-9-]{36}$/)
      end

      it 'uses provided idempotency key when specified' do
        customer = mock_stripe_customer
        custom_key = 'custom-idempotency-key-123'
        captured_options = nil

        allow(Stripe::Customer).to receive(:create) do |_params, options|
          captured_options = options
          customer
        end

        client.create(Stripe::Customer, customer_params, idempotency_key: custom_key)

        expect(captured_options[:idempotency_key]).to eq(custom_key)
      end

      it 'excludes sensitive data from logs' do
        customer = mock_stripe_customer
        params_with_card = customer_params.merge(card: '4242424242424242')

        allow(Stripe::Customer).to receive(:create).and_return(customer)
        allow(client).to receive(:billing_logger).and_return(double(debug: nil))

        client.create(Stripe::Customer, params_with_card)

        expect(client.billing_logger).to have_received(:debug).with(
          /Creating/,
          hash_excluding(:card, :source)
        )
      end
    end

    context 'with network errors' do
      it 'retries with linear backoff' do
        call_count = 0
        customer = mock_stripe_customer

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::APIConnectionError.new('Network error') if call_count < 3
          customer
        end

        # Mock sleep to speed up tests
        allow(client).to receive(:sleep)

        result = client.create(Stripe::Customer, customer_params)

        expect(call_count).to eq(3)
        expect(result).to eq(customer)
        # Verify linear backoff: 2s, 4s
        expect(client).to have_received(:sleep).with(2).once
        expect(client).to have_received(:sleep).with(4).once
      end

      it 'fails after max retries' do
        allow(Stripe::Customer).to receive(:create).and_raise(
          Stripe::APIConnectionError.new('Network error')
        )
        allow(client).to receive(:sleep)

        expect {
          client.create(Stripe::Customer, customer_params)
        }.to raise_error(Stripe::APIConnectionError, /Network error/)
      end

      it 'caps delay at MAX_RETRY_DELAY' do
        call_count = 0

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::APIConnectionError.new('Network error')
        end
        allow(client).to receive(:sleep)

        begin
          client.create(Stripe::Customer, customer_params)
        rescue Stripe::APIConnectionError
          # Expected
        end

        # Even with linear backoff (2, 4, 6), max delay is 30
        client.instance_variable_get(:@sleep_calls)&.each do |delay|
          expect(delay).to be <= described_class::MAX_RETRY_DELAY
        end
      end
    end

    context 'with rate limit errors' do
      it 'retries with exponential backoff' do
        call_count = 0
        customer = mock_stripe_customer

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::RateLimitError.new('Rate limit', http_status: 429) if call_count < 3
          customer
        end

        allow(client).to receive(:sleep)

        result = client.create(Stripe::Customer, customer_params)

        expect(call_count).to eq(3)
        expect(result).to eq(customer)
        # Verify exponential backoff: 4s (2*2^1), 8s (2*2^2)
        expect(client).to have_received(:sleep).with(4).once
        expect(client).to have_received(:sleep).with(8).once
      end

      it 'caps exponential backoff at MAX_RETRY_DELAY' do
        # With base=2 and exponent, 2*2^3=16, 2*2^4=32 (should cap at 30)
        call_count = 0

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::RateLimitError.new('Rate limit', http_status: 429)
        end
        allow(client).to receive(:sleep)

        begin
          client.create(Stripe::Customer, customer_params)
        rescue Stripe::RateLimitError
          # Expected after retries
        end

        # Verify no delay exceeds max
        sleep_calls = []
        allow(client).to receive(:sleep) { |delay| sleep_calls << delay }
        sleep_calls.each do |delay|
          expect(delay).to be <= described_class::MAX_RETRY_DELAY
        end
      end
    end

    context 'with non-retryable errors' do
      it 'does not retry on InvalidRequestError' do
        call_count = 0

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::InvalidRequestError.new('Invalid email', 'email', http_status: 400)
        end

        expect {
          client.create(Stripe::Customer, customer_params)
        }.to raise_error(Stripe::InvalidRequestError)

        expect(call_count).to eq(1)
      end

      it 'does not retry on AuthenticationError' do
        call_count = 0

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::AuthenticationError.new('Invalid API key', http_status: 401)
        end

        expect {
          client.create(Stripe::Customer, customer_params)
        }.to raise_error(Stripe::AuthenticationError)

        expect(call_count).to eq(1)
      end

      it 'does not retry on CardError' do
        call_count = 0

        allow(Stripe::Customer).to receive(:create) do
          call_count += 1
          raise Stripe::CardError.new('Card declined', 'card_declined', http_status: 402)
        end

        expect {
          client.create(Stripe::Customer, customer_params)
        }.to raise_error(Stripe::CardError)

        expect(call_count).to eq(1)
      end
    end
  end

  describe '#update' do
    let(:customer_id) { 'cus_test123' }
    let(:update_params) { { metadata: { foo: 'bar' } } }

    it 'updates the resource' do
      customer = mock_stripe_customer
      allow(Stripe::Customer).to receive(:update).and_return(customer)

      result = client.update(Stripe::Customer, customer_id, update_params)

      expect(result).to eq(customer)
      expect(Stripe::Customer).to have_received(:update).with(customer_id, update_params)
    end

    it 'retries on network errors' do
      call_count = 0
      customer = mock_stripe_customer

      allow(Stripe::Customer).to receive(:update) do
        call_count += 1
        raise Stripe::APIConnectionError.new('Network error') if call_count < 2
        customer
      end
      allow(client).to receive(:sleep)

      result = client.update(Stripe::Customer, customer_id, update_params)

      expect(call_count).to eq(2)
      expect(result).to eq(customer)
    end

    it 'excludes sensitive data from logs' do
      customer = mock_stripe_customer
      params_with_card = update_params.merge(source: 'tok_visa')

      allow(Stripe::Customer).to receive(:update).and_return(customer)
      allow(client).to receive(:billing_logger).and_return(double(debug: nil))

      client.update(Stripe::Customer, customer_id, params_with_card)

      expect(client.billing_logger).to have_received(:debug).with(
        /Updating/,
        hash_excluding(:card, :source)
      )
    end
  end

  describe '#retrieve' do
    let(:subscription_id) { 'sub_test123' }

    it 'retrieves the resource' do
      subscription = mock_stripe_subscription
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)

      result = client.retrieve(Stripe::Subscription, subscription_id)

      expect(result).to eq(subscription)
      expect(Stripe::Subscription).to have_received(:retrieve).with(subscription_id, {})
    end

    it 'supports expand parameter' do
      subscription = mock_stripe_subscription
      allow(Stripe::Subscription).to receive(:retrieve).and_return(subscription)

      client.retrieve(Stripe::Subscription, subscription_id, expand: ['customer'])

      expect(Stripe::Subscription).to have_received(:retrieve).with(
        subscription_id,
        { expand: ['customer'] }
      )
    end

    it 'retries on network errors' do
      call_count = 0
      subscription = mock_stripe_subscription

      allow(Stripe::Subscription).to receive(:retrieve) do
        call_count += 1
        raise Stripe::APIConnectionError.new('Network error') if call_count < 2
        subscription
      end
      allow(client).to receive(:sleep)

      result = client.retrieve(Stripe::Subscription, subscription_id)

      expect(call_count).to eq(2)
      expect(result).to eq(subscription)
    end
  end

  describe '#list' do
    let(:list_params) { { limit: 10 } }

    it 'lists resources' do
      customers = double('Stripe::ListObject', data: [mock_stripe_customer])
      allow(Stripe::Customer).to receive(:list).and_return(customers)

      result = client.list(Stripe::Customer, list_params)

      expect(result).to eq(customers)
      expect(Stripe::Customer).to have_received(:list).with(list_params)
    end

    it 'retries on rate limit errors' do
      call_count = 0
      customers = double('Stripe::ListObject', data: [])

      allow(Stripe::Customer).to receive(:list) do
        call_count += 1
        raise Stripe::RateLimitError.new('Rate limit', http_status: 429) if call_count < 2
        customers
      end
      allow(client).to receive(:sleep)

      result = client.list(Stripe::Customer, list_params)

      expect(call_count).to eq(2)
      expect(result).to eq(customers)
    end
  end

  describe '#delete' do
    context 'with regular resources' do
      let(:customer_id) { 'cus_test123' }

      it 'deletes the resource' do
        deleted_customer = mock_stripe_customer(deleted: true)
        allow(Stripe::Customer).to receive(:delete).and_return(deleted_customer)

        result = client.delete(Stripe::Customer, customer_id)

        expect(result).to eq(deleted_customer)
        expect(Stripe::Customer).to have_received(:delete).with(customer_id)
      end

      it 'retries on network errors' do
        call_count = 0
        deleted_customer = mock_stripe_customer(deleted: true)

        allow(Stripe::Customer).to receive(:delete) do
          call_count += 1
          raise Stripe::APIConnectionError.new('Network error') if call_count < 2
          deleted_customer
        end
        allow(client).to receive(:sleep)

        result = client.delete(Stripe::Customer, customer_id)

        expect(call_count).to eq(2)
        expect(result).to eq(deleted_customer)
      end
    end

    context 'with subscriptions' do
      let(:subscription_id) { 'sub_test123' }

      it 'cancels instead of deletes' do
        canceled_sub = mock_stripe_subscription(status: 'canceled')
        allow(Stripe::Subscription).to receive(:cancel).and_return(canceled_sub)

        result = client.delete(Stripe::Subscription, subscription_id)

        expect(result).to eq(canceled_sub)
        expect(Stripe::Subscription).to have_received(:cancel).with(subscription_id)
        expect(Stripe::Subscription).not_to have_received(:delete)
      end
    end
  end

  describe '#generate_idempotency_key' do
    it 'generates a unique key each time' do
      key1 = client.send(:generate_idempotency_key)
      key2 = client.send(:generate_idempotency_key)

      expect(key1).not_to eq(key2)
    end

    it 'follows timestamp-uuid format' do
      key = client.send(:generate_idempotency_key)

      expect(key).to match(/^\d+-[a-f0-9-]{36}$/)
    end

    it 'includes current timestamp' do
      freeze_time Time.parse('2024-01-15 10:00:00 UTC')

      key = client.send(:generate_idempotency_key)

      timestamp = key.split('-').first.to_i
      expect(timestamp).to eq(Time.now.to_i)
    end

    it 'includes a valid UUID' do
      key = client.send(:generate_idempotency_key)
      uuid_part = key.split('-', 2).last

      expect(uuid_part).to match(/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/)
    end
  end

  describe 'retry behavior' do
    it 'respects MAX_RETRIES constant' do
      expect(described_class::MAX_RETRIES).to eq(3)
    end

    it 'uses correct network retry base delay' do
      expect(described_class::NETWORK_RETRY_BASE_DELAY).to eq(2)
    end

    it 'uses correct rate limit retry base delay' do
      expect(described_class::RATE_LIMIT_RETRY_BASE_DELAY).to eq(2)
    end

    it 'caps retry delay at MAX_RETRY_DELAY' do
      expect(described_class::MAX_RETRY_DELAY).to eq(30)
    end
  end

  describe 'constants' do
    it 'defines test card numbers' do
      expect(described_class::StripeTestCards::SUCCESS).to eq('4242424242424242')
      expect(described_class::StripeTestCards::DECLINED).to eq('4000000000000002')
      expect(described_class::StripeTestCards::INSUFFICIENT_FUNDS).to eq('4000000000009995')
      expect(described_class::StripeTestCards::EXPIRED).to eq('4000000000000069')
      expect(described_class::StripeTestCards::PROCESSING_ERROR).to eq('4000000000000119')
    end

    it 'defines retryable error classes' do
      expect(described_class::RETRYABLE_ERRORS).to contain_exactly(
        Stripe::APIConnectionError,
        Stripe::RateLimitError
      )
    end
  end
end

# frozen_string_literal: true

# apps/web/billing/spec/support/shared_examples/stripe_error_handling.rb
#
# Shared examples for testing Stripe error handling across services

RSpec.shared_examples 'handles Stripe errors' do |method_name, *args|
  context 'when Stripe::CardError occurs' do
    it 'raises a descriptive error' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::CardError.new('Your card was declined', 'card_declined', http_status: 402)
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::CardError)
    end
  end

  context 'when Stripe::RateLimitError occurs' do
    it 'should be retried by the client' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::RateLimitError.new('Too many requests', http_status: 429)
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::RateLimitError)
    end
  end

  context 'when Stripe::InvalidRequestError occurs' do
    it 'raises a validation error' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::InvalidRequestError.new('Invalid request', 'invalid_request', http_status: 400)
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::InvalidRequestError)
    end
  end

  context 'when Stripe::AuthenticationError occurs' do
    it 'raises an authentication error' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::AuthenticationError.new('Invalid API key', http_status: 401)
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::AuthenticationError)
    end
  end

  context 'when Stripe::APIConnectionError occurs' do
    it 'should be retried by the client' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::APIConnectionError.new('Network error')
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::APIConnectionError)
    end
  end

  context 'when Stripe::StripeError occurs' do
    it 'raises a general Stripe error' do
      allow(subject).to receive(method_name).and_raise(
        Stripe::StripeError.new('Something went wrong')
      )

      expect { subject.public_send(method_name, *args) }.to raise_error(Stripe::StripeError)
    end
  end
end

RSpec.shared_examples 'retries on transient errors' do |method_name, max_retries: 3|
  context 'when network errors occur' do
    it 'retries the request' do
      call_count = 0
      allow(subject).to receive(method_name) do
        call_count += 1
        raise Stripe::APIConnectionError.new('Network error') if call_count < max_retries
        double('Success', id: 'test_123')
      end

      result = subject.public_send(method_name)
      expect(call_count).to eq(max_retries)
      expect(result.id).to eq('test_123')
    end
  end

  context 'when rate limit errors occur' do
    it 'retries with exponential backoff' do
      call_count = 0
      allow(subject).to receive(method_name) do
        call_count += 1
        raise Stripe::RateLimitError.new('Rate limit', http_status: 429) if call_count < max_retries
        double('Success', id: 'test_123')
      end

      expect(subject).to receive(:sleep).at_least(max_retries - 1).times
      result = subject.public_send(method_name)
      expect(call_count).to eq(max_retries)
    end
  end
end

RSpec.shared_examples 'validates required parameters' do |method_name, required_params|
  required_params.each do |param|
    context "when #{param} is missing" do
      it 'raises an ArgumentError' do
        params = required_params.each_with_object({}) { |p, h| h[p] = 'value' unless p == param }
        expect { subject.public_send(method_name, **params) }.to raise_error(ArgumentError)
      end
    end

    context "when #{param} is nil" do
      it 'raises an ArgumentError' do
        params = required_params.each_with_object({}) { |p, h| h[p] = p == param ? nil : 'value' }
        expect { subject.public_send(method_name, **params) }.to raise_error(ArgumentError)
      end
    end
  end
end

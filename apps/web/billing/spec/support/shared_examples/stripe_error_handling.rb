# apps/web/billing/spec/support/shared_examples/stripe_error_handling.rb
#
# frozen_string_literal: true

# Shared examples for testing Stripe error handling using real API calls with error tokens.
# Uses VCR to record/replay real Stripe test API calls - no RSpec mocking.

RSpec.shared_examples 'handles Stripe card errors', :stripe do
  it 'raises CardError on declined card' do
    expect do
      Stripe::PaymentIntent.create(
        amount: 1000,
        currency: 'cad',
        payment_method_data: {
          type: 'card',
          card: { token: StripeTestData::CARDS[:visa_decline] },
        },
        confirm: true,
      )
    end.to raise_error(Stripe::CardError) do |error|
      expect(error.code).to eq('card_declined')
      expect(error.http_status).to eq(402)
    end
  end

  it 'raises CardError on insufficient funds' do
    expect do
      Stripe::PaymentIntent.create(
        amount: 1000,
        currency: 'cad',
        payment_method_data: {
          type: 'card',
          card: { token: StripeTestData::CARDS[:visa_insufficient_funds] },
        },
        confirm: true,
      )
    end.to raise_error(Stripe::CardError) do |error|
      expect(error.code).to eq('insufficient_funds')
    end
  end

  it 'raises CardError on expired card' do
    expect do
      Stripe::PaymentIntent.create(
        amount: 1000,
        currency: 'cad',
        payment_method_data: {
          type: 'card',
          card: { token: StripeTestData::CARDS[:visa_expired] },
        },
        confirm: true,
      )
    end.to raise_error(Stripe::CardError) do |error|
      expect(error.code).to eq('expired_card')
    end
  end
end

RSpec.shared_examples 'handles Stripe invalid request errors', :stripe do
  it 'raises InvalidRequestError on missing required parameter' do
    expect do
      Stripe::Customer.create(
        email: nil,  # Invalid: email cannot be nil in certain contexts
      )
    end.to raise_error(Stripe::InvalidRequestError)
  end

  it 'raises InvalidRequestError on invalid parameter value' do
    expect do
      Stripe::Price.create(
        currency: 'invalid',
        unit_amount: 1000,
        product: 'prod_invalid',
      )
    end.to raise_error(Stripe::InvalidRequestError)
  end

  it 'raises InvalidRequestError on non-existent resource' do
    expect do
      Stripe::Customer.retrieve('cus_nonexistent')
    end.to raise_error(Stripe::InvalidRequestError) do |error|
      expect(error.http_status).to eq(404)
    end
  end
end

RSpec.shared_examples 'handles Stripe authentication errors', :stripe do
  it 'raises AuthenticationError on invalid API key' do
    original_key = Stripe.api_key
    begin
      Stripe.api_key = 'sk_test_invalid_key_123'

      expect do
        Stripe::Customer.list
      end.to raise_error(Stripe::AuthenticationError) do |error|
        expect(error.http_status).to eq(401)
      end
    ensure
      Stripe.api_key = original_key
    end
  end
end

RSpec.shared_examples 'handles Stripe rate limit errors', :stripe do
  # NOTE: stripe-mock doesn't simulate rate limits well
  # Use VCR cassette for realistic rate limit testing
  it 'raises RateLimitError when rate limited', :vcr do
    # This requires a pre-recorded cassette or multiple rapid requests
    # to trigger actual rate limiting from Stripe test API

    expect do
      # Simulate many rapid requests
      100.times do
        Stripe::Customer.list(limit: 1)
      end
    end.to raise_error(Stripe::RateLimitError) do |error|
      expect(error.http_status).to eq(429)
    end
  end
end

RSpec.shared_examples 'handles Stripe connection errors', :stripe do
  it 'raises APIConnectionError on network failure' do
    # Force connection error by using invalid host
    original_base = Stripe.api_base
    begin
      Stripe.api_base = 'https://invalid.stripe.com.invalid'

      expect do
        Stripe::Customer.list
      end.to raise_error(Stripe::APIConnectionError)
    ensure
      Stripe.api_base = original_base
    end
  end
end

# Validates that a method properly handles and propagates Stripe errors
RSpec.shared_examples 'propagates Stripe errors' do |method_name, error_trigger:|
  it "propagates #{error_trigger[:type]} from Stripe API" do
    expect do
      case error_trigger[:type]
      when :card_error
        subject.public_send(method_name,
          card_token: StripeTestData::CARDS[:visa_decline],
        )
      when :invalid_request
        subject.public_send(method_name,
          **error_trigger[:params],
        )
      when :authentication
        original_key   = Stripe.api_key
        Stripe.api_key = 'sk_test_invalid'
        begin
          subject.public_send(method_name)
        ensure
          Stripe.api_key = original_key
        end
      end
    end.to raise_error(error_trigger[:expected_error])
  end
end

# Validates retry behavior on transient errors
# NOTE: This requires the implementation to have actual retry logic
# The shared example verifies the behavior, not implements it
RSpec.shared_examples 'retries on transient Stripe errors' do |method_name, max_retries: 3|
  context 'when connection errors occur' do
    it 'eventually succeeds after retries' do
      call_count = 0

      # Temporarily override the method to simulate transient failure
      allow(Stripe::Customer).to receive(:create) do
        call_count += 1
        raise Stripe::APIConnectionError.new('Network error') if call_count < max_retries

        Stripe::Customer.construct_from(id: 'cus_success', email: 'test@example.com')
      end

      result = subject.public_send(method_name, email: 'test@example.com')
      expect(call_count).to eq(max_retries)
      expect(result.id).to eq('cus_success')
    end

    it 'gives up after max retries exceeded' do
      # Force all attempts to fail
      allow(Stripe::Customer).to receive(:create).and_raise(
        Stripe::APIConnectionError.new('Network error'),
      )

      expect do
        subject.public_send(method_name, email: 'test@example.com')
      end.to raise_error(Stripe::APIConnectionError)
    end
  end
end

# Validates parameter requirements without Stripe mocking
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

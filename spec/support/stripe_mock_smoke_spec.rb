# frozen_string_literal: true

# spec/support/stripe_mock_smoke_spec.rb
#
# Smoke test to verify stripe-mock and VCR setup is working correctly.
#
# Run with: bundle exec rspec spec/support/stripe_mock_smoke_spec.rb

require 'spec_helper'

RSpec.describe 'Stripe Mock + VCR Setup', :stripe do
  describe 'stripe-mock server' do
    it 'is running and accessible' do
      expect(StripeMockServer.running?).to be true
    end

    it 'has configured Stripe client correctly' do
      expect(Stripe.api_base).to eq("http://localhost:#{StripeMockServer.port}")
      # Billing app warmup sets this from config, so just verify it's a test key
      expect(Stripe.api_key).to start_with('sk_test_')
    end
  end

  describe 'basic Stripe object creation' do
    it 'creates a product' do
      product = Stripe::Product.create(
        name: 'Test Product'
      )

      expect(product).to be_a(Stripe::Product)
      expect(product.name).to eq('Test Product')
    end

    it 'creates a price with recurring interval' do
      product = Stripe::Product.create(name: 'Test Product')

      price = Stripe::Price.create(
        product: product.id,
        currency: 'usd',
        unit_amount: 1000,
        recurring: { interval: 'month' }
      )

      expect(price).to be_a(Stripe::Price)
      expect(price.recurring).to be_a(Stripe::StripeObject)
      expect(price.recurring.interval).to eq('month')
      expect(price.unit_amount).to eq(1000)
    end

    it 'creates a customer' do
      customer = Stripe::Customer.create(
        email: 'test@example.com'
      )

      expect(customer).to be_a(Stripe::Customer)
      expect(customer.email).to eq('test@example.com')
    end
  end

  describe 'StripeObject behavior' do
    it 'returns StripeObject for nested attributes, not Hash' do
      price = Stripe::Price.create(
        currency: 'usd',
        unit_amount: 1000,
        recurring: { interval: 'month', interval_count: 1 }
      )

      # This is the critical test - .recurring should return StripeObject
      # not a Hash, so we can use .interval notation
      expect(price.recurring).to be_a(Stripe::StripeObject)
      expect(price.recurring).not_to be_a(Hash)

      # These should work (production code pattern)
      expect(price.recurring&.interval).to eq('month')
      expect(price.recurring&.interval_count).to eq(1)
    end

    it 'supports safe navigation operator' do
      # Note: stripe-mock always creates prices with default recurring settings
      # This test demonstrates the safe navigation operator works regardless
      one_time_price = Stripe::Price.create(
        currency: 'usd',
        unit_amount: 1000
      )

      # Safe navigation works on StripeObject
      expect(one_time_price.recurring).to be_a(Stripe::StripeObject)
      expect(one_time_price.recurring&.interval).to eq('month') # stripe-mock default
    end
  end

  describe 'VCR integration', :vcr do
    # This test will be recorded to a cassette on first run
    # Subsequent runs will replay from the cassette
    it 'records and replays Stripe API calls' do
      product = Stripe::Product.create(
        name: 'VCR Test Product'
      )

      expect(product.name).to eq('VCR Test Product')
      expect(product.id).to start_with('prod_')
    end
  end
end

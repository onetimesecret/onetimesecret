# frozen_string_literal: true

# apps/web/billing/spec/support/billing_spec_helper.rb
#
# Billing-specific test helper that extends centralized spec helpers

require 'spec_helper'

module BillingSpecHelper
  # Create a mock Stripe::Customer object
  def mock_stripe_customer(id: 'cus_test123', **attrs)
    defaults = {
      id: id,
      email: 'test@example.com',
      name: 'Test Customer',
      metadata: {},
      created: Time.now.to_i,
      livemode: false
    }
    double('Stripe::Customer', defaults.merge(attrs))
  end

  # Create a mock Stripe::Subscription object
  def mock_stripe_subscription(id: 'sub_test123', **attrs)
    defaults = {
      id: id,
      customer: 'cus_test123',
      status: 'active',
      current_period_start: Time.now.to_i,
      current_period_end: (Time.now + 30.days).to_i,
      metadata: {},
      items: mock_stripe_subscription_items,
      created: Time.now.to_i,
      cancel_at_period_end: false
    }
    double('Stripe::Subscription', defaults.merge(attrs))
  end

  # Create mock Stripe::SubscriptionItem collection
  def mock_stripe_subscription_items(items: [])
    default_items = items.empty? ? [mock_stripe_subscription_item] : items
    double('Stripe::ListObject', data: default_items)
  end

  # Create a mock Stripe::SubscriptionItem
  def mock_stripe_subscription_item(id: 'si_test123', **attrs)
    defaults = {
      id: id,
      price: mock_stripe_price,
      quantity: 1
    }
    double('Stripe::SubscriptionItem', defaults.merge(attrs))
  end

  # Create a mock Stripe::Price object
  def mock_stripe_price(id: 'price_test123', **attrs)
    defaults = {
      id: id,
      product: 'prod_test123',
      unit_amount: 1000,
      currency: 'usd',
      recurring: { interval: 'month', interval_count: 1 },
      metadata: {},
      active: true
    }
    double('Stripe::Price', defaults.merge(attrs))
  end

  # Create a mock Stripe::Product object
  def mock_stripe_product(id: 'prod_test123', **attrs)
    defaults = {
      id: id,
      name: 'Test Product',
      description: 'Test product description',
      metadata: {},
      active: true,
      created: Time.now.to_i
    }
    double('Stripe::Product', defaults.merge(attrs))
  end

  # Create a mock Stripe::Invoice object
  def mock_stripe_invoice(id: 'in_test123', **attrs)
    defaults = {
      id: id,
      customer: 'cus_test123',
      subscription: 'sub_test123',
      status: 'paid',
      amount_due: 1000,
      amount_paid: 1000,
      currency: 'usd',
      created: Time.now.to_i,
      metadata: {}
    }
    double('Stripe::Invoice', defaults.merge(attrs))
  end

  # Create a mock Stripe::Charge object
  def mock_stripe_charge(id: 'ch_test123', **attrs)
    defaults = {
      id: id,
      customer: 'cus_test123',
      amount: 1000,
      currency: 'usd',
      status: 'succeeded',
      paid: true,
      refunded: false,
      amount_refunded: 0,
      metadata: {},
      created: Time.now.to_i
    }
    double('Stripe::Charge', defaults.merge(attrs))
  end

  # Create a mock Stripe::Refund object
  def mock_stripe_refund(id: 'ref_test123', **attrs)
    defaults = {
      id: id,
      charge: 'ch_test123',
      amount: 1000,
      currency: 'usd',
      status: 'succeeded',
      reason: nil,
      metadata: {},
      created: Time.now.to_i
    }
    double('Stripe::Refund', defaults.merge(attrs))
  end

  # Create a mock Stripe::PaymentMethod object
  def mock_stripe_payment_method(id: 'pm_test123', **attrs)
    defaults = {
      id: id,
      type: 'card',
      card: {
        brand: 'visa',
        last4: '4242',
        exp_month: 12,
        exp_year: Time.now.year + 2
      },
      metadata: {}
    }
    double('Stripe::PaymentMethod', defaults.merge(attrs))
  end

  # Create a mock Stripe::Event object
  def mock_stripe_event(type:, data_object:, **attrs)
    defaults = {
      id: "evt_#{SecureRandom.hex(12)}",
      type: type,
      data: { object: data_object },
      created: Time.now.to_i,
      livemode: false,
      api_version: '2023-10-16'
    }
    double('Stripe::Event', defaults.merge(attrs))
  end

  # Mock StripeClient for testing
  def mock_stripe_client
    client = instance_double('Billing::StripeClient')
    allow(Billing::StripeClient).to receive(:new).and_return(client)
    client
  end

  # Mock WebhookValidator for testing
  def mock_webhook_validator(valid: true)
    validator = instance_double('Billing::WebhookValidator')
    allow(validator).to receive(:validate!).and_return(valid)
    allow(Billing::WebhookValidator).to receive(:new).and_return(validator)
    validator
  end

  # Generate a valid Stripe webhook signature
  def generate_stripe_signature(payload:, secret:, timestamp: Time.now.to_i)
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), secret, signed_payload)
    "t=#{timestamp},v1=#{signature}"
  end

  # Mock Redis for billing tests
  def mock_billing_redis
    redis = double('Redis')
    allow(redis).to receive_messages(
      get: nil,
      set: 'OK',
      setex: 'OK',
      del: 1,
      exists: false,
      exists?: false,
      setnx: true,
      expire: true,
      ttl: -1,
      scan_each: []
    )
    allow(Familia).to receive(:dbclient).and_return(redis)
    redis
  end

  # Create a test Plan object
  def create_test_plan(**attrs)
    defaults = {
      stripe_price_id: 'price_test123',
      tier: 'personal',
      interval: 'month',
      region: 'US'
    }
    Billing::Models::Plan.new(defaults.merge(attrs))
  end

  # Stub Stripe API responses
  def stub_stripe_api
    # Stub common Stripe SDK methods
    allow(Stripe::Customer).to receive(:create).and_return(mock_stripe_customer)
    allow(Stripe::Customer).to receive(:retrieve).and_return(mock_stripe_customer)
    allow(Stripe::Customer).to receive(:update).and_return(mock_stripe_customer)

    allow(Stripe::Subscription).to receive(:create).and_return(mock_stripe_subscription)
    allow(Stripe::Subscription).to receive(:retrieve).and_return(mock_stripe_subscription)
    allow(Stripe::Subscription).to receive(:update).and_return(mock_stripe_subscription)

    allow(Stripe::Product).to receive(:list).and_return(double(data: [mock_stripe_product]))
    allow(Stripe::Price).to receive(:list).and_return(double(data: [mock_stripe_price]))
  end

  # Freeze time for time-sensitive tests
  def freeze_time(time = Time.now)
    allow(Time).to receive(:now).and_return(time)
    time
  end
end

RSpec.configure do |config|
  config.include BillingSpecHelper, type: :billing
  config.include BillingSpecHelper, type: :controller
  config.include BillingSpecHelper, type: :integration
  config.include BillingSpecHelper, type: :cli
end

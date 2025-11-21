# frozen_string_literal: true

# apps/web/billing/spec/support/billing_spec_helper.rb
#
# Billing-specific test helper that extends centralized spec helpers

require 'spec_helper'

# Load billing lib classes
require_relative '../../lib/stripe_client'
require_relative '../../lib/webhook_validator'

module BillingSpecHelper
  using Familia::Refinements::TimeLiterals

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

  # Mock Redis for billing tests with comprehensive Familia v2 support
  # Based on Familia::Horreum, Familia::DataType, and Familia::SortedSet
  # See: https://delanotes.com/familia/
  def mock_billing_redis
    redis = double('Redis')
    allow(redis).to receive_messages(
      # Key Management (Familia::DataType)
      exists: 0,
      exists?: false,
      del: 1,
      expire: true,
      expireat: true,
      ttl: -1,
      persist: true,
      rename: 'OK',
      renamenx: true,
      move: true,
      type: 'none',

      # String operations
      get: nil,
      set: 'OK',
      setex: 'OK',
      setnx: true,
      getset: nil,

      # Hash operations (Familia::Horreum primary persistence)
      hset: 1,
      hget: nil,
      hgetall: {},
      hmset: 'OK',
      hsetnx: true,
      hdel: 1,
      hexists: false,
      hkeys: [],
      hvals: [],
      hlen: 0,
      hstrlen: 0,

      # Counter operations (Familia::Horreum)
      incr: 1,
      incrby: 1,
      incrbyfloat: 1.0,
      decr: 0,
      decrby: 0,

      # Sorted Set operations (Familia::SortedSet)
      zadd: 1,
      zcard: 0,
      zscore: nil,
      zrank: nil,
      zrevrank: nil,
      zrange: [],
      zrevrange: [],
      zrangebyscore: [],
      zrevrangebyscore: [],
      zincrby: '1',
      zremrangebyrank: 0,
      zremrangebyscore: 0,
      zrem: 1,
      zcount: 0,

      # List operations
      lpush: 1,
      rpush: 1,
      lpop: nil,
      rpop: nil,
      lrange: [],
      llen: 0,
      lindex: nil,
      lset: 'OK',

      # Set operations
      sadd: 1,
      srem: 1,
      smembers: [],
      sismember: false,
      scard: 0,

      # Transaction operations (Familia::Horreum)
      multi: 'OK',
      exec: [],
      discard: 'OK',
      watch: 'OK',
      unwatch: 'OK',

      # Pipeline operations
      pipelined: [],

      # Utility commands
      echo: 'PONG',
      ping: 'PONG',
      flushdb: 'OK',
      info: '',
      scan_each: []
    )

    # Allow transaction blocks to execute
    allow(redis).to receive(:multi) do |&block|
      block ? block.call : 'OK'
    end

    allow(redis).to receive(:pipelined) do |&block|
      block ? block.call : []
    end

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

  # Prevent automatic plan cache refresh during tests
  def prevent_plan_refresh
    # Skip plan refresh in Billing application initialization
    if defined?(Billing::Plan)
      allow(Billing::Plan).to receive(:refresh_from_stripe).and_return(true)
    end
  end

  # Freeze time for time-sensitive tests using Timecop
  def freeze_time(time = Time.now)
    Timecop.freeze(time)
    time
  end

  # Travel to a specific time
  def travel_to(time)
    Timecop.travel(time)
  end

  # Travel forward in time by a duration
  def travel(duration)
    Timecop.travel(duration)
  end

  # Get tracked sleep delays for retry testing
  def sleep_delays
    @sleep_delays || []
  end

  # Verify retry delays match expected pattern
  def expect_retry_delays(*expected_delays)
    expect(sleep_delays).to eq(expected_delays)
  end

  # Verify exponential backoff pattern
  def expect_exponential_backoff(base: 2, count: 3)
    expected = (1..count).map { |i| base * (2 ** i) }
    expect(sleep_delays).to eq(expected)
  end

  # Verify linear backoff pattern
  def expect_linear_backoff(base: 2, count: 3)
    expected = (1..count).map { |i| base * i }
    expect(sleep_delays).to eq(expected)
  end
end

RSpec.configure do |config|
  config.include BillingSpecHelper, type: :billing
  config.include BillingSpecHelper, type: :controller
  config.include BillingSpecHelper, type: :integration
  config.include BillingSpecHelper, type: :cli

  # Set up billing test environment before each test
  config.before(:each, type: :billing) do
    mock_billing_redis
    prevent_plan_refresh

    # Track sleep calls for retry testing
    @sleep_delays = []
    allow_any_instance_of(Billing::StripeClient).to receive(:sleep) do |_, delay|
      @sleep_delays << delay
    end
  end

  config.before(:each, type: :cli) do
    mock_billing_redis
    prevent_plan_refresh

    # Track sleep calls for retry testing (only if StripeClient is loaded)
    @sleep_delays = []
    if defined?(Billing::StripeClient)
      allow_any_instance_of(Billing::StripeClient).to receive(:sleep) do |_, delay|
        @sleep_delays << delay
      end
    end

    # Mock global sleep to prevent delays in CLI retry logic
    allow_any_instance_of(Object).to receive(:sleep) do |_, delay|
      @sleep_delays << delay if delay.is_a?(Numeric)
    end
  end

  config.before(:each, type: :controller) do
    mock_billing_redis
    prevent_plan_refresh
  end

  config.before(:each, type: :integration) do
    mock_billing_redis
    prevent_plan_refresh
  end
end

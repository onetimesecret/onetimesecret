# frozen_string_literal: true

# apps/web/billing/spec/support/billing_spec_helper.rb
#
# Billing-specific test helper that extends centralized spec helpers
#
# This file now uses stripe-ruby-mock for all Stripe object creation.
# Factory methods for creating Stripe objects have been moved to
# spec/support/stripe_test_data.rb which creates real Stripe objects
# through the stripe-mock server.

require 'spec_helper'

# Load billing lib classes
require_relative '../../lib/stripe_client'
require_relative '../../lib/webhook_validator'

module BillingSpecHelper
  using Familia::Refinements::TimeLiterals

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

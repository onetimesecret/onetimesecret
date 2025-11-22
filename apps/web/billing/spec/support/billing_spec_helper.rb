# frozen_string_literal: true

# apps/web/billing/spec/support/billing_spec_helper.rb
#
# Minimal test helpers for billing specs.
# Timecop time manipulation and retry delay tracking only.
#
# All Stripe mocking will be done via stripe-mock server + VCR.

require 'spec_helper'
require 'openssl'

# Configure Familia to use test Redis on port 2121
ENV['VALKEY_URL'] ||= 'valkey://127.0.0.1:2121/0'
ENV['REDIS_URL'] ||= 'redis://127.0.0.1:2121/0'

# Force Familia to reconnect with the test URL
Familia.reset! if Familia.respond_to?(:reset!)

module BillingSpecHelper
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
    expected = (1..count).map { |i| base * (2**i) }
    expect(sleep_delays).to eq(expected)
  end

  # Verify linear backoff pattern
  def expect_linear_backoff(base: 2, count: 3)
    expected = (1..count).map { |i| base * i }
    expect(sleep_delays).to eq(expected)
  end

  # Generate valid Stripe webhook signature
  #
  # Uses Stripe's official signature generation algorithm.
  # This creates a real signature that will pass Stripe.Webhook.construct_event validation.
  #
  # @param payload [String] Raw webhook payload
  # @param secret [String] Webhook signing secret
  # @param timestamp [Integer] Unix timestamp (defaults to current time)
  # @return [String] Stripe-Signature header value
  #
  def generate_stripe_signature(payload:, secret:, timestamp: nil)
    timestamp ||= Time.now.to_i

    # Stripe signature format: t={timestamp},v1={signature}
    # Signature is HMAC-SHA256 of "{timestamp}.{payload}"
    signed_payload = "#{timestamp}.#{payload}"
    signature = OpenSSL::HMAC.hexdigest('SHA256', secret, signed_payload)

    "t=#{timestamp},v1=#{signature}"
  end
end

RSpec.configure do |config|
  config.include BillingSpecHelper, type: :billing
  config.include BillingSpecHelper, type: :controller
  config.include BillingSpecHelper, type: :integration
  config.include BillingSpecHelper, type: :cli

  # Billing tests use REAL Redis on port 2121 (not FakeRedis)
  # This ensures proper state isolation and matches production behavior
  config.before(:each, type: :billing) do
    @sleep_delays = []

    # Flush test Redis to ensure clean slate
    # Uses Familia.dbclient which connects to redis://127.0.0.1:2121/0
    Familia.dbclient.flushdb
  end

  config.after(:each, type: :billing) do
    # Clean up test data after each test
    Familia.dbclient.flushdb
  end

  config.before(:each, type: :cli) do
    @sleep_delays = []

    # Mock global sleep to prevent delays in CLI retry logic
    allow_any_instance_of(Object).to receive(:sleep) do |_, delay|
      @sleep_delays << delay if delay.is_a?(Numeric)
    end
  end

  config.before(:each, type: :controller) do
    @sleep_delays = []
  end

  config.before(:each, type: :integration) do
    @sleep_delays = []
  end
end

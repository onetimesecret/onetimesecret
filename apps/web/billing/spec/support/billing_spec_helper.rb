# apps/web/billing/spec/support/billing_spec_helper.rb
#
# frozen_string_literal: true

#
# Minimal test helpers for billing specs.
# Timecop time manipulation and retry delay tracking only.
#
# All Stripe mocking will be done via stripe-mock server + VCR.

# IMPORTANT: Set test environment BEFORE loading anything
# These must be set before OT.boot! reads config files
ENV['VALKEY_URL'] ||= 'valkey://127.0.0.1:2121/0'
ENV['STRIPE_KEY'] ||= 'sk_test_mock'
ENV['RACK_ENV'] ||= 'test'

require 'spec_helper'
require 'openssl'
require 'stripe'

# Load Stripe testing infrastructure
require_relative 'stripe_mock_server'
require_relative 'vcr_setup'

# Load BannedIP model needed by IPBan middleware
require_relative '../../../../api/colonel/models/banned_ip'

# Ensure BillingConfig picks up the test environment
# The singleton may have been created before RACK_ENV was set to 'test'
# (e.g., if shell has RACK_ENV=development). Reload to use billing.test.yaml.
Onetime::BillingConfig.instance.reload!

# Run full boot process for billing integration tests
# This initializes Familia, locales, billing config, and sets ready flag
OT.boot! unless OT.ready?

# Set Stripe.api_key for tests that call Stripe SDK directly
# STRIPE_API_KEY takes precedence (for real API/VCR recording)
Stripe.api_key = ENV['STRIPE_API_KEY'] || OT.billing_config.stripe_key

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
    signature      = OpenSSL::HMAC.hexdigest('SHA256', secret, signed_payload)

    "t=#{timestamp},v1=#{signature}"
  end
end

RSpec.configure do |config|
  # Include BillingSpecHelper for both `type:` metadata and symbol tags
  # e.g., `type: :integration` AND `:integration` symbol tag
  config.include BillingSpecHelper, type: :billing
  config.include BillingSpecHelper, type: :controller
  config.include BillingSpecHelper, type: :integration
  config.include BillingSpecHelper, type: :cli
  # Symbol tag matching (for RSpec.describe 'Name', :integration do)
  config.include BillingSpecHelper, integration: true
  config.include BillingSpecHelper, billing_cli: true

  # stripe-mock is NOT used for integration tests
  # Integration tests use VCR to record/replay real Stripe API calls
  # Only start stripe-mock for tests explicitly tagged with :stripe_mock
  config.before(:each, :stripe_mock) do
    StripeMockServer.start unless StripeMockServer.running?
    StripeMockServer.configure_stripe_client!
  end

  config.after(:suite) do
    StripeMockServer.stop if StripeMockServer.instance_variable_get(:@pid)
  end

  # VCR: Automatically wrap tests tagged with :vcr in cassettes
  config.around(:each, :vcr) do |example|
    # Generate cassette name from test description
    cassette_name = example.metadata[:full_description]
      .downcase
      .gsub(/[^\w\s]/, '')
      .gsub(/\s+/, '_')

    VCR.use_cassette(cassette_name) do
      example.run
    end
  end

  # Billing tests use REAL Redis on port 2121 (not FakeRedis)
  # This ensures proper state isolation and matches production behavior
  config.before(:each, type: :billing) do
    @sleep_delays = []

    # Mock global sleep to prevent actual delays in retry logic tests
    # Tracks all sleep calls for verification in retry behavior tests
    allow_any_instance_of(Object).to receive(:sleep) do |_, delay|
      @sleep_delays << delay if delay.is_a?(Numeric)
    end

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

  # Symbol tag matching for :integration (webhook controller tests use this pattern)
  config.before(:each, integration: true) do
    @sleep_delays = []
    # Flush test Redis to ensure clean slate
    Familia.dbclient.flushdb
  end

  config.after(:each, integration: true) do
    # Clean up test data after each test
    Familia.dbclient.flushdb
  end
end

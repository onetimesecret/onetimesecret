# apps/web/billing/spec/support/billing_spec_helper.rb
#
# frozen_string_literal: true

#
# Minimal test helpers for billing specs.
# Timecop time manipulation and retry delay tracking only.
#
# Stripe API testing uses VCR to record/replay real API calls.
# Record cassettes with: STRIPE_API_KEY=sk_test_xxx VCR_MODE=all bundle exec rspec

# IMPORTANT: Set test environment BEFORE loading anything
# These must be set before OT.boot! reads config files
ENV['STRIPE_KEY'] ||= 'sk_test_mock'
ENV['RACK_ENV']   ||= 'test'

# Use SQLite for auth database in billing tests
# Stripe data is stored in Redis, not the auth DB, so we don't need PostgreSQL
ENV['AUTHENTICATION_MODE'] ||= 'full'
ENV['AUTH_DATABASE_URL'] ||= 'sqlite::memory:'

require 'spec_helper'
require 'openssl'
require 'stripe'

# Load Stripe testing infrastructure (VCR for recording/replaying real API calls)
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

  # Skip VCR tests in CI when cassettes may be invalid
  # Re-record cassettes locally with: STRIPE_API_KEY=sk_test_xxx VCR_MODE=all bundle exec rspec
  config.before(:each, :vcr) do
    if defined?(BILLING_VCR_SKIP_IN_CI) && BILLING_VCR_SKIP_IN_CI
      skip 'Skipping VCR test in CI - cassettes need re-recording with real Stripe API key'
    end
  end

  # VCR: Automatically wrap tests tagged with :vcr in cassettes
  # Cassette naming matches existing directory structure:
  #   Billing_StripeClient/_delete/deletes_regular_resources.yml
  config.around(:each, :vcr) do |example|
    # Extract class name and method from example group
    # e.g., "Billing::StripeClient" -> "Billing_StripeClient"
    class_name = example.metadata[:described_class]&.to_s&.gsub('::', '_') || 'Unknown'

    # Extract method name from parent group description (e.g., "#delete" -> "_delete")
    method_desc = example.metadata[:example_group][:description] rescue nil
    method_name = method_desc&.gsub(/^#/, '_')&.gsub(/\s+.*/, '') || '_unknown'

    # Extract test description (e.g., "deletes regular resources" -> "deletes_regular_resources")
    # Preserve case and hyphens to match existing cassette filenames
    test_desc = example.metadata[:description]
      .gsub(/[^\w\s\-]/, '')
      .gsub(/\s+/, '_')

    # Build hierarchical cassette path: Class/_method/test_description
    cassette_name = "#{class_name}/#{method_name}/#{test_desc}"

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
  config.before(:each, :integration) do
    @sleep_delays = []
    # Flush test Redis to ensure clean slate
    Familia.dbclient.flushdb
  end

  config.after(:each, :integration) do
    # Clean up test data after each test
    Familia.dbclient.flushdb
  end
end

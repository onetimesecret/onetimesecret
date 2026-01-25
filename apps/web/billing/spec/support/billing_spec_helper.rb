# apps/web/billing/spec/support/billing_spec_helper.rb
#
# frozen_string_literal: true

#
# Minimal test helpers for billing specs.
# Timecop time manipulation and retry delay tracking only.
#
# Stripe API testing uses VCR to record/replay real API calls.
# Record cassettes with: STRIPE_API_KEY=sk_test_xxx rake vcr:billing:record

# IMPORTANT: Set test environment BEFORE loading anything
# These must be set before OT.boot! reads config files
ENV['STRIPE_API_KEY'] ||= 'sk_test_mock'
ENV['REDIS_URL'] ||= 'redis://127.0.0.1:2121/0'
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

# Load StripeMockFactory for creating Stripe API mock objects
require_relative 'stripe_mock_factory'

# Load shared RSpec contexts for billing tests
Dir[File.join(__dir__, 'shared_contexts', '*.rb')].sort.each { |f| require f }

# Load BannedIP model needed by IPBan middleware
require_relative '../../../../api/colonel/models/banned_ip'

# Load billing models (includes WebhookSyncFlag needed by webhook handlers)
require_relative '../../models'

# NOTE: Billing config is mocked in before(:each) blocks.
# Tests should not depend on etc/billing.yaml existing.

# Run full boot process for billing integration tests
# This initializes Familia, locales, billing config, and sets ready flag
OT.boot! unless OT.ready?

# Set Stripe.api_key for tests that call Stripe SDK directly
# STRIPE_API_KEY takes precedence (for real API/VCR recording)
Stripe.api_key = ENV['STRIPE_API_KEY'] || OT.billing_config.stripe_key

module BillingSpecHelper
  # Mock billing config for tests
  # When STRIPE_API_KEY is set (recording mode), use the real key
  # Otherwise use a mock key for cassette playback
  def mock_billing_config!
    allow(OT.billing_config).to receive(:enabled?).and_return(true)

    # Use real API key for recording, mock key for playback
    stripe_key = ENV['STRIPE_API_KEY'] || 'sk_test_mock'
    allow(OT.billing_config).to receive(:stripe_key).and_return(stripe_key)
  end

  # Mock region configuration for plan lookups
  # Tests need a valid region (e.g., 'EU') to match cached Stripe plans
  def mock_region!(region = 'EU')
    # Override the detect_region method on all billing controllers
    allow_any_instance_of(Billing::Controllers::Base).to receive(:region).and_return(region)
  end

  # Mock sleep to prevent delays and track calls
  def mock_sleep!
    @sleep_delays = []
    allow_any_instance_of(Object).to receive(:sleep) do |_, delay|
      @sleep_delays << delay if delay.is_a?(Numeric)
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
    expected = (1..count).map { |i| base * (2**i) }
    expect(sleep_delays).to eq(expected)
  end

  # Verify linear backoff pattern
  def expect_linear_backoff(base: 2, count: 3)
    expected = (1..count).map { |i| base * i }
    expect(sleep_delays).to eq(expected)
  end

  # Stub catalog lookups for test price IDs
  #
  # With catalog-first design, Billing::PlanValidator.resolve_plan_id raises
  # CatalogMissError when price_id isn't in the catalog. This helper stubs
  # Billing::Plan.find_by_stripe_price_id to return mock plans for common
  # test price IDs (price_test, price_test_mock, etc).
  #
  # Call this in before(:each) blocks for tests that process subscriptions.
  #
  def stub_test_plan_catalog!
    # Create a mock plan that responds to plan_id
    mock_plan = instance_double(
      Billing::Plan,
      plan_id: 'test_plan_v1_monthly',
      stripe_price_id: 'price_test',
      stripe_product_id: 'prod_test',
      tier: 'single_team',
      interval: 'month',
      amount: '1900',
      currency: 'cad',
    )

    # Stub find_by_stripe_price_id to return mock plan for test price IDs
    allow(Billing::Plan).to receive(:find_by_stripe_price_id).and_call_original
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with('price_test')
      .and_return(mock_plan)
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with('price_test_mock')
      .and_return(mock_plan)
    allow(Billing::Plan).to receive(:find_by_stripe_price_id)
      .with(satisfy { |id| id&.start_with?('price_test_') })
      .and_return(mock_plan)
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

  # Include StripeMockFactory for Stripe API mock objects
  config.include StripeMockFactory, type: :billing
  config.include StripeMockFactory, type: :controller
  config.include StripeMockFactory, type: :integration
  config.include StripeMockFactory, integration: true

  # Build VCR cassette name from example metadata
  # Returns hierarchical path: Class/_method/test_description
  def vcr_cassette_name(example)
    # e.g., "Billing::StripeClient" -> "Billing_StripeClient"
    # Falls back to top-level description when described_class is nil
    # (happens when RSpec.describe uses a string instead of a class)
    class_name = example.metadata[:described_class]&.to_s ||
                 example.example_group.top_level_description
    class_name = class_name&.gsub('::', '_')&.gsub(/\s+/, '_') || 'Unknown'

    # e.g., "#delete" -> "_delete"
    method_desc = example.metadata[:example_group][:description] rescue nil
    method_name = method_desc&.gsub(/^#/, '_')&.gsub(/\s+.*/, '') || '_unknown'

    # e.g., "deletes regular resources" -> "deletes_regular_resources"
    test_desc = example.metadata[:description]
      .gsub(/[^\w\s\-]/, '')
      .gsub(/\s+/, '_')

    "#{class_name}/#{method_name}/#{test_desc}"
  end

  # VCR: Wrap ALL billing tests in cassettes automatically
  # No need to tag individual tests with :vcr
  #
  # IMPORTANT: Skip stripe_sandbox_api tests in CI when STRIPE_API_KEY is not set
  # This must happen BEFORE VCR.use_cassette to avoid replaying stale cassettes
  %i[billing cli controller integration].each do |test_type|
    config.around(:each, type: test_type) do |example|
      if BILLING_VCR_SKIP_IN_CI && example.metadata[:stripe_sandbox_api]
        skip 'Skipping Stripe sandbox test in CI - re-record cassettes with STRIPE_API_KEY'
      else
        VCR.use_cassette(vcr_cassette_name(example)) do
          example.run
        end
      end
    end
  end

  # Symbol tag :integration also gets VCR wrapping
  config.around(:each, :integration) do |example|
    if BILLING_VCR_SKIP_IN_CI && example.metadata[:stripe_sandbox_api]
      skip 'Skipping Stripe sandbox test in CI - re-record cassettes with STRIPE_API_KEY'
    else
      VCR.use_cassette(vcr_cassette_name(example)) do
        example.run
      end
    end
  end

  # Billing tests use REAL Redis on port 2121 (not FakeRedis)
  # Supports both `type: :billing` and `:billing` symbol tag patterns
  billing_setup = lambda do |_example|
    mock_billing_config!
    mock_sleep!
    stub_test_plan_catalog!
    Familia.dbclient.flushdb
  end

  billing_cleanup = ->(_example = nil) { Familia.dbclient.flushdb }

  config.before(:each, type: :billing, &billing_setup)
  config.before(:each, :billing, &billing_setup)
  config.after(:each, type: :billing, &billing_cleanup)
  config.after(:each, :billing, &billing_cleanup)

  config.before(:each, type: :cli) do
    mock_billing_config!
    mock_sleep!
  end

  config.before(:each, type: :controller) do
    @sleep_delays = []
    mock_billing_config!
  end

  # Integration tests: both `type: :integration` and `:integration` symbol tag
  # get the same setup. Using a shared proc for consistency.
  # Note: stripe_sandbox_api skip logic is handled in the around hooks above
  integration_setup = lambda do |_example|
    @sleep_delays = []
    mock_billing_config!
    stub_test_plan_catalog!
    Familia.dbclient.flushdb
  end

  config.before(:each, type: :integration, &integration_setup)
  config.before(:each, :integration, &integration_setup)

  # Cleanup for both integration tag patterns
  integration_cleanup = ->(_example = nil) { Familia.dbclient.flushdb }
  config.after(:each, type: :integration, &integration_cleanup)
  config.after(:each, :integration, &integration_cleanup)
end

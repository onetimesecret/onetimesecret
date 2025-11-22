# frozen_string_literal: true

# apps/web/billing/spec/support/billing_spec_helper.rb
#
# Minimal test helpers for billing specs.
# Timecop time manipulation and retry delay tracking only.
#
# All Stripe mocking will be done via stripe-mock server + VCR.

require 'spec_helper'

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
end

RSpec.configure do |config|
  config.include BillingSpecHelper, type: :billing
  config.include BillingSpecHelper, type: :controller
  config.include BillingSpecHelper, type: :integration
  config.include BillingSpecHelper, type: :cli

  # Track sleep calls for retry testing
  config.before(:each, type: :billing) do
    @sleep_delays = []
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

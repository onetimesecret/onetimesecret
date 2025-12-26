# apps/web/billing/spec/support/billing_isolation.rb
#
# frozen_string_literal: true

# RSpec-specific billing test isolation.
# Configures RSpec hooks to disable billing by default and provides
# tag-based opt-in for tests that need billing enabled.
#
# Framework-agnostic helpers live in lib/test_support/billing_helpers.rb

require_relative '../../lib/test_support/billing_helpers'

RSpec.configure do |config|
  # Disable billing before each test by default
  config.before(:each) do
    BillingTestHelpers.disable_billing!
  end

  # Clean up billing state after tests that enable it
  config.after(:each) do
    if @billing_enabled_in_test
      BillingTestHelpers.cleanup_billing_state!
      @billing_enabled_in_test = false
    end
  end

  # Tag support: tests can use `billing: true` to enable billing
  config.before(:each, billing: true) do
    @billing_enabled_in_test = true
    BillingTestHelpers.restore_billing!
  end

  # Billing CLI tests need billing enabled
  config.before(:each, billing_cli: true) do
    @billing_enabled_in_test = true
    BillingTestHelpers.restore_billing!
  end

  # Integration tests tagged with :stripe_sandbox_api need billing enabled
  config.before(:each, stripe_sandbox_api: true) do
    @billing_enabled_in_test = true
    BillingTestHelpers.restore_billing!
  end
end

# Helper methods available in specs
module BillingSpecHelpers
  def with_billing_enabled(plans: [], &block)
    @billing_enabled_in_test = true
    BillingTestHelpers.with_billing_enabled(plans: plans, &block)
  end

  def setup_test_plan(plan_data)
    BillingTestHelpers.populate_test_plans([plan_data])
  end
end

RSpec.configure do |config|
  config.include BillingSpecHelpers
end

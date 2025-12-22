# frozen_string_literal: true

# spec/support/billing_isolation.rb
#
# RSpec-specific billing isolation using shared helpers.
# Ensures billing is disabled before each test and cleaned up after.

require_relative '../../try/support/billing_helpers'

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
end

# Helper method available in specs
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

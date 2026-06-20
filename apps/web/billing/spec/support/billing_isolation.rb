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

  # Disable billing before each example group's context hooks, too.
  #
  # before(:context)/before(:all) hooks run BEFORE the first before(:each), so a
  # spec that exercises billing-sensitive logic in before(:all) -- e.g. creating
  # an Organization that materializes STANDALONE_ENTITLEMENTS at create! time --
  # would otherwise observe whatever BILLING_ENABLED the environment or a prior
  # example happened to leave set. Under the `billing: on` CI matrix that default
  # is "true", which makes Organization.create! treat the org as SaaS and skip
  # standalone materialization, producing a suite-order-dependent flake where the
  # outcome tracks the RSpec seed rather than the code (issue #3418).
  #
  # This mirrors the before(:each) default at the context scope so the billing
  # default is deterministic for before(:all) setup as well. It is safe by
  # construction: the `billing: off` CI matrix already runs every group's
  # before(:all) with billing disabled, so disabling here cannot introduce new
  # failures. Groups that need billing enabled during before(:all) opt back in
  # explicitly within their own before(:all) (e.g. BillingTestHelpers.restore_billing!),
  # which runs after this hook; per-example billing is unaffected and continues
  # to opt in via the `billing: true` before(:each) hook below.
  config.before(:context) do
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
    BillingTestHelpers.restore_billing!(enabled: true)
  end

  # Billing CLI tests need billing enabled
  config.before(:each, billing_cli: true) do
    @billing_enabled_in_test = true
    BillingTestHelpers.restore_billing!(enabled: true)
  end

  # Integration tests tagged with :stripe_sandbox_api need billing enabled
  config.before(:each, stripe_sandbox_api: true) do
    @billing_enabled_in_test = true
    BillingTestHelpers.restore_billing!(enabled: true)
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

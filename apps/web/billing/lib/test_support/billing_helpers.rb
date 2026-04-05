# apps/web/billing/lib/test_support/billing_helpers.rb
#
# frozen_string_literal: true

# Framework-agnostic billing test helpers.
# Used by both RSpec and Tryouts for billing state management.
#
# This module provides methods to disable/enable billing, clear caches,
# and manage test state. It has no test framework dependencies.

module BillingTestHelpers
  class << self
    # Disable billing globally for tests by resetting the singleton
    # ConfigResolver will return nil when no billing config exists in spec/
    def disable_billing!
      ensure_familia_configured!
      reset_billing_singleton!
    end

    # Restore billing configuration for tests that need it
    # Resets singleton so it reloads from ConfigResolver
    #
    # @param enabled [Boolean] When true, force billing to be enabled regardless
    #   of config file setting. Default: false (use config file value).
    #   This is essential for tests that need plan-based entitlements rather
    #   than standalone mode.
    def restore_billing!(enabled: false)
      ensure_familia_configured!
      ensure_billing_loaded! if enabled
      clear_plan_cache!
      reset_billing_singleton!

      # Override config file setting with the enabled parameter value
      Onetime::BillingConfig.instance.config['enabled'] = enabled
    end

    # Load billing module if not already defined
    # Required for tests that need billing functionality when billing
    # plugin was not loaded at boot time (true plugin extraction per #2887)
    def ensure_billing_loaded!
      return if defined?(::Billing::Plan)

      # Load the billing models which define the Billing module
      # Use absolute path to ensure it works regardless of $LOAD_PATH
      billing_models_path = File.expand_path('../../models/plan', __dir__)
      require billing_models_path
    end

    # Ensure Familia is configured with test Redis URI
    # Must be called before any Familia operations if OT.conf isn't loaded
    #
    # NOTE: We avoid reconfiguring if Familia is already connected to avoid
    # disrupting the test infrastructure's Redis connection pool.
    def ensure_familia_configured!
      # Skip if already configured for test port OR if already connected
      return if Familia.uri.to_s.include?('2121')

      begin
        return if Familia.dbclient.connected?
      rescue StandardError
        false
      end

      # Use test Redis port from ENV (set by test_helpers.rb)
      test_uri    = ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:2121/0'
      Familia.uri = test_uri
    end

    # Clear plan cache in Redis
    # Essential after tests that populate the cache
    def clear_plan_cache!
      return unless defined?(::Billing::Plan)

      ensure_familia_configured!
      ::Billing::Plan.clear_cache
    rescue StandardError => ex
      warn "[BillingTestHelpers] Failed to clear plan cache: #{ex.message}"
    end

    # Full billing state cleanup
    def cleanup_billing_state!
      clear_plan_cache!
      disable_billing!
    end

    # Enable billing for a test block
    # Automatically cleans up afterward
    def with_billing_enabled(plans: [])
      restore_billing!(enabled: true)
      populate_test_plans(plans) if plans.any?
      yield
    ensure
      cleanup_billing_state!
    end

    # Populate Redis plan cache with test data
    def populate_test_plans(plans)
      ensure_familia_configured!
      plans.each do |plan_data|
        plan                                                    = ::Billing::Plan.new(plan_data.slice(:plan_id, :name, :tier, :interval, :region))
        (plan_data[:entitlements] || []).each { |e| plan.entitlements.add(e) }
        (plan_data[:limits] || {}).each { |k, v| plan.limits[k] = v.to_s }
        plan.save
      end
    end

    private

    def reset_billing_singleton!
      Onetime::BillingConfig.instance_variable_set(:@singleton__instance__, nil)
    end
  end
end

# frozen_string_literal: true

# Shared billing test isolation helpers for Tryouts and RSpec.
# Ensures billing is disabled by default for all tests, with opt-in
# for tests that specifically need billing enabled.

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
    def restore_billing!
      ensure_familia_configured!
      reset_billing_singleton!
    end

    # Ensure Familia is configured with test Redis URI
    # Must be called before any Familia operations if OT.conf isn't loaded
    #
    # NOTE: We avoid reconfiguring if Familia is already connected to avoid
    # disrupting the test infrastructure's Redis connection pool.
    def ensure_familia_configured!
      # Skip if already configured for test port OR if already connected
      return if Familia.uri.to_s.include?('2121')
      return if Familia.redis.connected? rescue false

      # Use test Redis port from ENV (set by test_helpers.rb)
      test_uri = ENV['VALKEY_URL'] || ENV['REDIS_URL'] || 'redis://127.0.0.1:2121/0'
      Familia.uri = test_uri
    end

    # Clear plan cache in Redis
    # Essential after tests that populate the cache
    def clear_plan_cache!
      return unless defined?(::Billing::Plan)

      ensure_familia_configured!
      ::Billing::Plan.clear_cache
    rescue StandardError => e
      warn "[BillingTestHelpers] Failed to clear plan cache: #{e.message}"
    end

    # Full billing state cleanup
    def cleanup_billing_state!
      clear_plan_cache!
      disable_billing!
    end

    # Enable billing for a test block
    # Automatically cleans up afterward
    def with_billing_enabled(plans: [])
      restore_billing!
      populate_test_plans(plans) if plans.any?
      yield
    ensure
      cleanup_billing_state!
    end

    # Populate Redis plan cache with test data
    def populate_test_plans(plans)
      ensure_familia_configured!
      plans.each do |plan_data|
        plan = ::Billing::Plan.new(plan_data.slice(:plan_id, :name, :tier, :interval, :region))
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

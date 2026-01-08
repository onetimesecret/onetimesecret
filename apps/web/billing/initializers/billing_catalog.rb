# apps/web/billing/initializers/billing_catalog.rb
#
# frozen_string_literal: true

require_relative '../models/plan'

module Billing
  module Initializers
    # Load billing plan catalog from Stripe
    #
    # Refreshes the plan cache from Stripe on application boot.
    # Optional - failure won't halt boot (degraded functionality).
    class BillingCatalog < Onetime::Boot::Initializer
      @depends_on = [:database, :stripe]
      @provides   = [:billing_catalog]
      @optional   = true

      def should_skip?
        return true unless Onetime.billing_config.enabled?
        return true if ENV['RACK_ENV'] == 'test'

        false
      end

      def execute(_context)
        if catalog_valid?
          Onetime.billing_logger.info 'Cache valid, skipping Stripe sync'
          return
        end

        Onetime.billing_logger.info 'Refreshing plan cache from Stripe'
        begin
          Billing::Plan.refresh_from_stripe
          Onetime.billing_logger.info 'Plan cache refreshed successfully'
        rescue StandardError => ex
          Onetime.billing_logger.warn 'Stripe sync failed, falling back to billing.yaml', {
            exception: ex,
            message: ex.message,
          }

          # Fallback to local config when Stripe is unavailable
          begin
            count = Billing::Plan.load_all_from_config
            Onetime.billing_logger.info "Loaded #{count} plans from billing.yaml fallback"
          rescue StandardError => fallback_ex
            Onetime.billing_logger.error 'Fallback to billing.yaml also failed', {
              exception: fallback_ex,
              message: fallback_ex.message,
            }
            raise fallback_ex
          end
        end
      end

      private

      # Check if catalog cache is valid (populated and not stale)
      #
      # A catalog is considered valid when:
      # 1. The instances sorted set is not empty
      # 2. At least one plan was synced within the staleness threshold
      #
      # @return [Boolean] true if cache is valid and sync can be skipped
      def catalog_valid?
        # Empty catalog = invalid
        return false if Billing::Plan.instances.empty?

        # Check if any plan was synced recently (within 12 hours)
        sample_plan = Billing::Plan.list_plans.first
        return false unless sample_plan&.last_synced_at

        # Calculate staleness (last_synced_at is stored as Unix timestamp string)
        last_sync     = sample_plan.last_synced_at.to_i
        staleness     = Time.now.to_i - last_sync
        max_staleness = 12 * 60 * 60 # 12 hours in seconds

        staleness < max_staleness
      end
    end
  end
end

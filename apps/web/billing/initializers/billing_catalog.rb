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
    end
  end
end

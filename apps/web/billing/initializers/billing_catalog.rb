# apps/web/billing/initializers/billing_catalog.rb
#
# frozen_string_literal: true

module Billing
  module Initializers
    # Load billing plan catalog from Stripe
    #
    # Refreshes the plan cache from Stripe on application boot.
    # Optional - failure won't halt boot (degraded functionality).
    class BillingCatalog < Onetime::Boot::Initializer
      @depends_on = [:database, :stripe]
      @provides = [:billing_catalog]
      @optional = true

      def execute(_context)
        Onetime.billing_logger.info 'Refreshing plan cache from Stripe'
        begin
          Billing::Plan.refresh_from_stripe
          Onetime.billing_logger.info 'Plan cache refreshed successfully'
        rescue StandardError => ex
          Onetime.billing_logger.error 'Failed to refresh plan cache', {
            exception: ex,
            message: ex.message,
          }
          raise # Re-raise to mark initializer as failed
        end
      end
    end
  end
end

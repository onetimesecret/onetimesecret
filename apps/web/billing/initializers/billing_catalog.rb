# apps/web/billing/initializers/billing_catalog.rb
#
# frozen_string_literal: true

# Load billing plan catalog from Stripe
#
# Self-registering initializer that refreshes the plan cache from Stripe
# on application boot. This ensures billing plans are available for
# subscription operations.
#
# Depends on: :database (for caching plans), :stripe (API client)
# Provides: :billing_catalog capability
# Optional: Failure won't halt boot (degraded functionality)
#
Billing::Application.initializer(
  :billing_catalog,
  description: 'Load billing plan catalog from Stripe',
  depends_on: [:database, :stripe],
  provides: [:billing_catalog],
  optional: true
) do |_ctx|
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

# apps/web/billing/initializers/stripe_setup.rb
#
# frozen_string_literal: true

module Billing
  module Initializers
    # Configure Stripe API client
    #
    # Sets up the Stripe SDK with API key and version from billing configuration.
    class StripeSetup < Onetime::Boot::Initializer
      @depends_on = [:config]
      @provides = [:stripe]

      def execute(_context)
        stripe_key = Onetime.billing_config.stripe_key
        stripe_api_version = Onetime.billing_config.stripe_api_version

        if stripe_key && !stripe_key.to_s.strip.empty?
          Stripe.api_key = stripe_key
          Stripe.api_version = stripe_api_version if stripe_api_version
          Onetime.billing_logger.info 'Stripe API configured', {
            api_version: stripe_api_version || 'default'
          }
        else
          Onetime.billing_logger.warn 'Stripe API key not configured - billing features disabled'
        end
      end
    end
  end
end

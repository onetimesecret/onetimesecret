# apps/web/billing/initializers/stripe_setup.rb
#
# frozen_string_literal: true

module Billing
  module Initializers
    # Configure Stripe API client
    #
    # Sets up the Stripe SDK with API key and version from billing configuration.
    class StripeSetup < Onetime::Boot::Initializer
      # No dependencies - OT.conf is available before initializers run
      @depends_on = [:logging]
      @provides   = [:stripe]

      def should_skip?
        !Onetime.billing_config.enabled?
      end

      def execute(_context)
        # Don't bring Stripe into this unless billing is enabled
        require 'stripe'

        stripe_key         = Onetime.billing_config.stripe_key
        stripe_api_version = Onetime.billing_config.stripe_api_version

        if stripe_key && !stripe_key.to_s.strip.empty?
          Stripe.api_key     = stripe_key
          Stripe.api_version = stripe_api_version if stripe_api_version
          Onetime.billing_logger.info 'Stripe API configured', {
            api_version: stripe_api_version || 'default',
          }
        else
          Onetime.billing_logger.warn 'Stripe API key not configured - billing features disabled'
        end
      end
    end
  end
end

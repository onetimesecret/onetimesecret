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

        # Secure debug logging - log key presence and prefix, never the full key
        key_status = if stripe_key.nil?
                       'nil'
                     elsif stripe_key.to_s.strip.empty?
                       'empty'
                     else
                       "present (prefix: #{stripe_key[0..7]}..., length: #{stripe_key.length})"
                     end

        Onetime.billing_logger.debug '[StripeSetup] Checking Stripe configuration', {
          stripe_key_status: key_status,
          env_key_present: !ENV['STRIPE_API_KEY'].to_s.strip.empty?,
          config_enabled: Onetime.billing_config.enabled?,
        }

        if stripe_key && !stripe_key.to_s.strip.empty?
          Stripe.api_key     = stripe_key
          Stripe.api_version = stripe_api_version if stripe_api_version
          Onetime.billing_logger.info 'Stripe API configured', {
            api_version: stripe_api_version || 'default',
            key_prefix: stripe_key[0..7],
          }
        else
          Onetime.billing_logger.warn 'Stripe API key not configured - billing features disabled'
        end
      end
    end
  end
end

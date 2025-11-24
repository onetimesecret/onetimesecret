# apps/web/billing/initializers/stripe_config.rb
#
# frozen_string_literal: true

# Configure Stripe API client
#
# Self-registering initializer that configures the Stripe SDK with
# API key and version from billing configuration.
#
# Depends on: None (reads from Onetime.billing_config)
# Provides: :stripe capability for other initializers
#
Billing::Application.initializer(
  :stripe_config,
  description: 'Configure Stripe API client',
  depends_on: [],
  provides: [:stripe]
) do |_ctx|
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

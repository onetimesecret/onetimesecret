# frozen_string_literal: true

module Onetime
  module Initializers
    # Initialize billing configuration and Stripe API when enabled.
    #
    # This initializer only runs when:
    # 1. etc/billing.yaml exists
    # 2. billing.enabled is set to true
    #
    # If billing is not enabled, this silently returns without error.
    #
    def configure_billing
      return unless OT.billing_config.enabled?

      stripe_key = OT.billing_config.stripe_key
      unless stripe_key
        raise OT::Problem, 'Billing enabled but no stripe_key found in etc/billing.yaml'
      end

      require 'stripe'
      Stripe.api_key = stripe_key

      OT.li '[init] Billing enabled with Stripe'
    end
  end
end

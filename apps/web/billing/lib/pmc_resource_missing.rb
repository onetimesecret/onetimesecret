# apps/web/billing/lib/pmc_resource_missing.rb
#
# frozen_string_literal: true

module Billing
  # Detection + operator messaging for the one payment_method_configuration
  # failure the boot-time format check cannot catch: a format-valid pmc_...
  # id that does not exist in the connected Stripe account (wrong account,
  # live/test mode mismatch, or deleted configuration). Per ADR-033 remote
  # validity is deliberately checked at first use, so first use must fail
  # loudly and point at the config.
  #
  # Shared by both checkout-creation call sites
  # (Operations::CreateCheckoutLink and Controllers::Plans#checkout_redirect);
  # each logs {operator_message} through its own logging idiom. This module
  # only discriminates and phrases — it never changes what the end user sees
  # and never touches any other Stripe error.
  module PmcResourceMissing
    module_function

    PARAM = 'payment_method_configuration'

    # True only for Stripe's resource_missing InvalidRequestError that names
    # payment_method_configuration — via the structured param when present,
    # falling back to the message text. Every other error (including a
    # resource_missing on a different param) is not ours to reinterpret.
    #
    # @param ex [Exception]
    # @return [Boolean]
    def pmc_resource_missing?(ex)
      return false unless ex.is_a?(Stripe::InvalidRequestError)
      return false unless ex.code.to_s == 'resource_missing'

      ex.param.to_s == PARAM || (ex.param.to_s.empty? && ex.message.to_s.include?(PARAM))
    end

    # Operator-actionable message naming the configured value, what is wrong,
    # the likely causes, and where the value is configured. Log-only; never
    # surfaced to the end user.
    #
    # @param ex [Stripe::InvalidRequestError]
    # @return [String]
    def operator_message(ex)
      pmc = Onetime.billing_config.payment_method_configuration
      "Stripe rejected payment_method_configuration #{pmc.inspect}: it does not " \
        'exist in the connected Stripe account. Likely causes: wrong Stripe ' \
        'account, live/test mode mismatch, or the configuration was deleted. ' \
        'Configured via ENV STRIPE_PAYMENT_METHOD_CONFIGURATION or billing.yaml ' \
        "payment_method_configuration. Stripe error: #{ex.message}"
    end
  end
end

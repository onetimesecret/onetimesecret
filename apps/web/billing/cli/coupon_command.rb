# apps/web/billing/cli/coupon_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Parent help command for `billing coupon` subcommands.
    # Use `billing coupons` (plural) to list all coupons.
    class BillingCouponCommand < Command
      include BillingHelpers

      desc 'Inspect or validate a single coupon / promotion code'

      def call(**)
        puts <<~HELP
          Coupon Commands:

            bin/ots billing coupons                  List all Stripe coupons
            bin/ots billing coupon validate <CODE>   Check if a code is currently valid

          Examples:
            # List all coupons with their promo codes
            bin/ots billing coupons

            # Only show coupons currently redeemable
            bin/ots billing coupons --valid-only

            # Validate a promotion code customers can type at checkout
            bin/ots billing coupon validate WELCOME20

            # Validate by coupon ID
            bin/ots billing coupon validate cou_abc123

        HELP
      end
    end
  end
end

Onetime::CLI.register 'billing coupon', Onetime::CLI::BillingCouponCommand

# apps/web/billing/cli/coupons_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe coupons (with attached promotion codes)
    class BillingCouponsCommand < Command
      include BillingHelpers

      desc 'List Stripe coupons and their promotion codes'

      option :limit, type: :integer, default: 100, desc: 'Maximum coupons to return'
      option :valid_only,
        type: :boolean,
        default: false,
        desc: 'Only show coupons currently redeemable (valid=true)'

      def call(limit: 100, valid_only: false, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching coupons from Stripe...'
        coupons = Stripe::Coupon.list(limit: limit)
        coupons = coupons.data
        coupons = coupons.select(&:valid) if valid_only

        if coupons.empty?
          puts 'No coupons found'
          return
        end

        puts format(
          '%-22s %-20s %-12s %-12s %-12s %-7s %s',
          'COUPON ID',
          'NAME',
          'DISCOUNT',
          'DURATION',
          'REDEEMED',
          'VALID',
          'PROMO CODES',
        )
        puts '-' * 110

        coupons.each do |coupon|
          puts format_coupon_row(coupon)
        end

        puts "\nTotal: #{coupons.size} coupon(s)"
        puts "\nUse 'bin/ots billing coupon validate <CODE>' to inspect a code in detail."
      rescue Stripe::StripeError => ex
        puts format_stripe_error('Failed to list coupons', ex)
      end

      private

      def format_coupon_row(coupon)
        name        = coupon.name || coupon.id
        discount    = format_discount(coupon)
        duration    = format_duration(coupon)
        redeemed    = redemption_summary(coupon)
        valid_str   = coupon.valid ? 'yes' : 'no'
        promo_codes = lookup_promotion_codes(coupon.id)

        format(
          '%-22s %-20s %-12s %-12s %-12s %-7s %s',
          coupon.id[0..21],
          name[0..19],
          discount[0..11],
          duration[0..11],
          redeemed[0..11],
          valid_str,
          promo_codes[0..40],
        )
      end

      def format_discount(coupon)
        if coupon.percent_off
          "#{format('%g', coupon.percent_off)}% off"
        elsif coupon.amount_off
          "#{format_amount(coupon.amount_off, coupon.currency)} off"
        else
          'N/A'
        end
      end

      def format_duration(coupon)
        case coupon.duration
        when 'repeating'
          "#{coupon.duration_in_months}mo"
        else
          coupon.duration.to_s
        end
      end

      def redemption_summary(coupon)
        if coupon.max_redemptions
          "#{coupon.times_redeemed}/#{coupon.max_redemptions}"
        else
          coupon.times_redeemed.to_s
        end
      end

      # Look up promotion codes attached to this coupon.
      # Returns a compact comma-separated string of the customer-facing codes,
      # or '(none)' if there are no active promotion codes.
      def lookup_promotion_codes(coupon_id)
        codes = Stripe::PromotionCode.list(coupon: coupon_id, limit: 10)
        return '(none)' if codes.data.empty?

        active = codes.data.select(&:active).map(&:code)
        return '(none active)' if active.empty?

        active.join(', ')
      rescue Stripe::StripeError
        '?'
      end
    end
  end
end

Onetime::CLI.register 'billing coupons', Onetime::CLI::BillingCouponsCommand

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

        # Batch-fetch active promotion codes once and group by coupon ID, so we
        # avoid one Stripe API call per coupon (N+1).
        #
        # NOTE: Stripe caps a single list page at 100. If there are more than
        # 100 active promotion codes in this account, this command will only
        # show the first page. Add pagination here if that limit becomes real.
        promo_codes_by_coupon = group_promotion_codes_by_coupon

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
          puts format_coupon_row(coupon, promo_codes_by_coupon)
        end

        puts "\nTotal: #{coupons.size} coupon(s)"
        puts "\nUse 'bin/ots billing coupon validate <CODE>' to inspect a code in detail."
      rescue Stripe::StripeError => ex
        puts format_stripe_error('Failed to list coupons', ex)
      end

      private

      def format_coupon_row(coupon, promo_codes_by_coupon)
        name        = coupon.name || coupon.id
        discount    = format_discount(coupon)
        duration    = format_duration(coupon)
        redeemed    = redemption_summary(coupon)
        valid_str   = coupon.valid ? 'yes' : 'no'
        promo_codes = promo_codes_for(coupon.id, promo_codes_by_coupon)

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

      # Fetch active promotion codes in a single API call and return them
      # grouped by their underlying coupon ID. Any error here propagates up
      # to the command's top-level rescue so the user sees a real message
      # rather than silent fallback values.
      def group_promotion_codes_by_coupon
        codes = Stripe::PromotionCode.list(active: true, limit: 100).data
        codes.group_by { |pc| pc.coupon.is_a?(String) ? pc.coupon : pc.coupon.id }
      end

      def promo_codes_for(coupon_id, promo_codes_by_coupon)
        codes = promo_codes_by_coupon[coupon_id]
        return '(none active)' if codes.nil? || codes.empty?

        codes.map(&:code).join(', ')
      end
    end
  end
end

Onetime::CLI.register 'billing coupons', Onetime::CLI::BillingCouponsCommand

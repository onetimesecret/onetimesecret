# apps/web/billing/cli/coupon_validate_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Validate a coupon or promotion code and show its details.
    #
    # Accepts either:
    #   - a promotion code string customers type at checkout (e.g. WELCOME20)
    #   - a Stripe coupon ID (e.g. WELCOME20 if used as the coupon ID, or
    #     a custom/auto-generated coupon ID like a3F9bC2D)
    #
    # The promotion code lookup is case-sensitive (Stripe stores codes
    # case-sensitively but matches case-insensitively at checkout).
    class BillingCouponValidateCommand < Command
      include BillingHelpers

      desc 'Check whether a coupon or promotion code is currently valid'

      argument :code,
        required: true,
        desc: 'Promotion code string (e.g. WELCOME20) or coupon ID (cou_xxx)'

      def call(code:, **)
        boot_application!

        return unless stripe_configured?

        coupon, promo_code = resolve_code(code)

        unless coupon
          puts "✗ No matching promotion code or coupon found for: #{code}"
          puts
          puts 'Hints:'
          puts '  - Promotion codes are case-sensitive when looked up via the API'
          puts '  - Make sure the code exists in the same Stripe mode (test vs live)'
          puts '    as your STRIPE_API_KEY'
          exit_with_status(1)
          return
        end

        print_summary(coupon, promo_code)
        print_restrictions(coupon, promo_code)
        print_validity(coupon, promo_code)
      rescue Stripe::StripeError => ex
        puts format_stripe_error('Failed to validate code', ex)
        exit_with_status(1)
      end

      private

      # Look up the input as either a promotion code or a coupon ID.
      #
      # Strategy:
      #   1. Try Stripe::PromotionCode.list(code:) — matches the customer-facing
      #      string. Returns the most recent active match.
      #   2. Fall back to Stripe::Coupon.retrieve(code) for direct coupon ID
      #      lookups (works for both auto-generated and custom coupon IDs).
      #
      # @return [Array(Stripe::Coupon, Stripe::PromotionCode|nil)]
      def resolve_code(code)
        # Promotion codes are limited to a-zA-Z0-9, so anything Stripe-shaped
        # works either as a promo code or a coupon ID.
        codes = Stripe::PromotionCode.list(code: code, limit: 5)
        if codes.data.any?
          # Prefer active codes when there are multiple matches.
          promo_code = codes.data.find(&:active) || codes.data.first
          return [promo_code.coupon, promo_code]
        end

        coupon = Stripe::Coupon.retrieve(code)
        [coupon, nil]
      rescue Stripe::InvalidRequestError
        [nil, nil]
      end

      def print_summary(coupon, promo_code)
        puts 'Coupon details:'
        puts "  Coupon ID:    #{coupon.id}"
        puts "  Name:         #{coupon.name || '(none)'}"
        puts "  Discount:     #{format_discount(coupon)}"
        puts "  Duration:     #{format_duration(coupon)}"
        puts "  Created:      #{format_timestamp(coupon.created)}"
        puts "  Redeemed:     #{redemption_summary(coupon)}"
        puts

        return unless promo_code

        puts 'Promotion code:'
        puts "  Code:         #{promo_code.code}"
        puts "  ID:           #{promo_code.id}"
        puts "  Active:       #{promo_code.active ? 'yes' : 'no'}"
        if promo_code.expires_at
          puts "  Expires at:   #{format_timestamp(promo_code.expires_at)}"
        end
        if promo_code.max_redemptions
          puts "  Redeemed:     #{promo_code.times_redeemed}/#{promo_code.max_redemptions}"
        end
        if promo_code.customer
          puts "  Customer:     #{promo_code.customer} (restricted to this customer)"
        end
        puts
      end

      def print_restrictions(coupon, promo_code)
        restrictions = []

        if coupon.amount_off && coupon.currency
          restrictions << "Coupon is denominated in #{coupon.currency.upcase} — only " \
                          'applies to checkouts in that currency.'
        end
        if coupon.applies_to&.products&.any?
          restrictions << "Coupon limited to products: #{coupon.applies_to.products.join(', ')}"
        end
        if coupon.redeem_by
          restrictions << "Coupon redemption deadline: #{format_timestamp(coupon.redeem_by)}"
        end

        restrictions_for_promo_code(promo_code, restrictions) if promo_code

        return if restrictions.empty?

        puts 'Restrictions:'
        restrictions.each { |r| puts "  - #{r}" }
        puts
      end

      def restrictions_for_promo_code(promo_code, restrictions)
        if promo_code.restrictions&.first_time_transaction
          restrictions << 'Only valid on a customer\'s first transaction'
        end
        if (min = promo_code.restrictions&.minimum_amount)
          min_currency = promo_code.restrictions.minimum_amount_currency
          restrictions << "Minimum order amount: #{format_amount(min, min_currency)}"
        end
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def print_validity(coupon, promo_code)
        # When a promotion code is present, both it and the coupon must be valid.
        problems = []

        problems << 'Coupon is not valid (likely max redemptions reached or redeem_by passed)' unless coupon.valid
        problems << 'Promotion code is not active' if promo_code && !promo_code.active
        if promo_code&.expires_at && promo_code.expires_at < Time.now.to_i
          problems << "Promotion code expired at #{format_timestamp(promo_code.expires_at)}"
        end
        if promo_code&.max_redemptions && promo_code.times_redeemed >= promo_code.max_redemptions
          problems << 'Promotion code has reached its max redemptions'
        end

        if problems.empty?
          puts '✓ Code is currently valid and can be applied at checkout'
        else
          puts '✗ Code is NOT currently valid:'
          problems.each { |p| puts "  - #{p}" }
          exit_with_status(1)
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity

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
        when 'once'      then 'once'
        when 'forever'   then 'forever'
        when 'repeating' then "repeating (#{coupon.duration_in_months} month(s))"
        else coupon.duration.to_s
        end
      end

      def redemption_summary(coupon)
        if coupon.max_redemptions
          "#{coupon.times_redeemed} / #{coupon.max_redemptions}"
        else
          "#{coupon.times_redeemed} (no max)"
        end
      end

      # CLI exit helper that respects the no-exit pattern under tests.
      def exit_with_status(status)
        exit(status) unless ENV['RACK_ENV'] == 'test'
      end
    end
  end
end

Onetime::CLI.register 'billing coupon validate', Onetime::CLI::BillingCouponValidateCommand

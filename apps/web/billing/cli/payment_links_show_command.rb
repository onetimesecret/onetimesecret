# apps/web/billing/cli/payment_links_show_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Show payment link details
    class BillingPaymentLinksShowCommand < Command
      include BillingHelpers

      desc 'Show payment link details'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      def call(link_id:, **)
        boot_application!

        return unless stripe_configured?

        # Ensure link_id is a string
        link_id = link_id.to_s.strip if link_id.respond_to?(:strip)
        link_id = link_id.first.to_s.strip if link_id.is_a?(Array)

        # Retrieve the payment link
        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment Link Details:"
        puts "  ID: #{link.id}"
        puts "  URL: #{link.url}"
        puts "  Active: #{link.active ? 'yes' : 'no'}"
        puts

        # Try to get line items - Stripe requires expand parameter
        begin
          link_with_items = Stripe::PaymentLink.retrieve(link_id, expand: ['line_items'])

          if link_with_items.line_items && link_with_items.line_items.data.any?
            line_item = link_with_items.line_items.data.first

            # Get price ID - handle both string and object
            price_id = line_item.price.is_a?(String) ? line_item.price : line_item.price.id
            price = Stripe::Price.retrieve(price_id)

            # Get product ID - handle both string and object
            product_id = price.product.is_a?(String) ? price.product : price.product.id
            product = Stripe::Product.retrieve(product_id)

            puts "Product:"
            puts "  ID: #{product.id}"
            puts "  Name: #{product.name}"
            puts

            puts "Price:"
            puts "  ID: #{price.id}"
            puts "  Amount: #{format_amount(price.unit_amount, price.currency)}"
            puts "  Interval: #{price.recurring&.interval || 'one-time'}"
            puts

            puts "Configuration:"
            quantity_text = line_item.adjustable_quantity&.enabled ? '(adjustable)' : '(fixed)'
            puts "  Quantity: #{line_item.quantity} #{quantity_text}"

            if link.after_completion && link.after_completion.redirect
              puts "  After completion: #{link.after_completion.redirect.url}"
            end
          else
            puts "Line Items:"
            puts "  (none configured)"
          end
        rescue StandardError => e
          puts "Line Items:"
          puts "  Error retrieving: #{e.message}"
          OT.logger.debug { "Line items error for #{link_id}: #{e.message}\n#{e.backtrace.first(5).join("\n")}" }
        end

      rescue Stripe::StripeError => e
        puts "Error retrieving payment link: #{e.message}"
      rescue StandardError => e
        puts "Error: #{e.message}"
        puts e.backtrace.first(5).join("\n") if OT.debug?
      end
    end
  end
end

Onetime::CLI.register 'billing payment-links show', Onetime::CLI::BillingPaymentLinksShowCommand

# apps/web/billing/cli/payment_links_create_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create payment link
    class BillingPaymentLinksCreateCommand < Command
      include BillingHelpers

      desc 'Create a new payment link'

      option :price, type: :string, required: true, desc: 'Price ID (price_xxx)'
      option :quantity, type: :integer, default: 1, desc: 'Fixed quantity'
      option :allow_quantity, type: :boolean, default: false,
        desc: 'Allow customer to adjust quantity'
      option :after_completion, type: :string,
        desc: 'Redirect URL after successful payment'

      def call(price:, quantity: 1, allow_quantity: false, after_completion: nil, **)
        boot_application!

        return unless stripe_configured?

        # Retrieve price to show details
        price_obj = Stripe::Price.retrieve(price)
        product = Stripe::Product.retrieve(price_obj.product)

        puts "Price: #{price}"
        puts "Product: #{product.name}"
        puts "Amount: #{format_amount(price_obj.unit_amount, price_obj.currency)}/#{price_obj.recurring&.interval || 'one-time'}"
        puts

        puts "Creating payment link..."

        link_params = {
          line_items: [{
            price: price,
            quantity: quantity,
            adjustable_quantity: allow_quantity ? { enabled: true } : nil
          }.compact]
        }

        if after_completion
          link_params[:after_completion] = {
            type: 'redirect',
            redirect: { url: after_completion }
          }
        end

        link = Stripe::PaymentLink.create(link_params)

        puts "\nPayment link created successfully:"
        puts "  ID: #{link.id}"
        puts "  URL: #{link.url}"
        puts "\nShare this link with customers!"

      rescue Stripe::StripeError => e
        puts "Error creating payment link: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing payment-links create', Onetime::CLI::BillingPaymentLinksCreateCommand

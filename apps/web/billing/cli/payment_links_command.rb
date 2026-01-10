# apps/web/billing/cli/payment_links_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List payment links
    class BillingPaymentLinksCommand < Command
      include BillingHelpers

      desc 'List Stripe payment links'

      option :active_only,
        type: :boolean,
        default: true,
        desc: 'Show only active links'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(active_only: true, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching payment links from Stripe...'
        params          = { limit: limit }
        params[:active] = true if active_only

        links = Stripe::PaymentLink.list(params)

        if links.data.empty?
          puts 'No payment links found'
          return
        end

        puts format(
          '%-30s %-30s %-12s %-10s %s',
          'ID',
          'PRODUCT/PRICE',
          'AMOUNT',
          'INTERVAL',
          'ACTIVE',
        )
        puts '-' * 100

        links.data.each do |link|
          active       = link.active ? 'yes' : 'no'
          product_name = 'N/A'
          amount       = 'N/A'
          interval     = 'N/A'

          begin
            # Retrieve with line_items expanded for each link
            link_expanded = Stripe::PaymentLink.retrieve(link.id, expand: ['line_items'])

            if link_expanded.line_items && link_expanded.line_items.data.any?
              line_item = link_expanded.line_items.data.first

              # Get price ID - handle both string and object
              price_id = line_item.price.is_a?(String) ? line_item.price : line_item.price.id
              price    = Stripe::Price.retrieve(price_id)

              # Get product ID - handle both string and object
              product_id = price.product.is_a?(String) ? price.product : price.product.id
              product    = Stripe::Product.retrieve(product_id)

              product_name = product.name[0..29]
              amount       = format_amount(price.unit_amount, price.currency)
              interval     = price.recurring&.interval || 'one-time'
            end
          rescue Stripe::StripeError => ex
            # Continue with N/A values if we can't fetch details from Stripe
            OT.logger.warn { "Stripe error fetching details for #{link.id}: #{ex.message}" }
          rescue StandardError => ex
            OT.logger.error { "Unexpected error fetching details for #{link.id}: #{ex.class}: #{ex.message}" }
          end

          puts format(
            '%-30s %-30s %-12s %-10s %s',
            link.id,
            product_name,
            amount[0..11],
            interval[0..9],
            active,
          )
        end

        puts "\nTotal: #{links.data.size} payment link(s)"
        puts "\nUse 'bin/ots billing payment-links show <id>' for full details including URL"
      rescue Stripe::StripeError => ex
        puts "Error fetching payment links: #{ex.message}"
      rescue StandardError => ex
        puts "Error: #{ex.message}"
        puts ex.backtrace.first(5).join("\n") if OT.debug?
      end
    end
  end
end

Onetime::CLI.register 'billing payment-links', Onetime::CLI::BillingPaymentLinksCommand

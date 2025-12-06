# apps/web/billing/cli/products_events_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Show product-related events
    class BillingProductsEventsCommand < Command
      include BillingHelpers

      desc 'Show product-related Stripe events'

      argument :product_id, required: true, desc: 'Product ID (e.g., prod_xxx)'

      option :limit, type: :integer, default: 20, desc: 'Maximum results to return'
      option :type, type: :string,
        desc: 'Filter by specific event type (e.g., product.updated)'

      def call(product_id:, limit: 20, type: nil, **)
        boot_application!

        return unless stripe_configured?

        # Verify product exists
        product = Stripe::Product.retrieve(product_id)
        puts "Product Events for: #{product.name} (#{product_id})"
        puts

        # Fetch events related to this product
        params        = { limit: 100 }  # Fetch more to filter
        params[:type] = type if type

        events = Stripe::Event.list(params)

        # Filter events related to this product
        product_events = events.data.select do |event|
          event_data = event.data.object

          # Check if event is about this product
          case event.type
          when /^product\./
            event_data.id == product_id
          when /^price\./
            # Price events - check if price belongs to this product
            event_data.respond_to?(:product) &&
              (event_data.product == product_id || event_data.product&.id == product_id)
          else
            false
          end
        end.first(limit)

        if product_events.empty?
          puts 'No events found for this product'
          puts "\nTip: Events are only stored for 30 days by Stripe"
          return
        end

        puts format('%-22s %-35s %-12s %s',
          'ID', 'TYPE', 'LIVEMODE', 'CREATED'
        )
        puts '-' * 85

        product_events.each do |event|
          livemode = event.livemode ? 'live' : 'test'
          created  = format_timestamp(event.created)

          puts format('%-22s %-35s %-12s %s',
            event.id[0..21],
            event.type[0..34],
            livemode,
            created,
          )
        end

        puts "\nTotal: #{product_events.size} event(s)"
        puts "\nFor details: bin/ots billing events --type product.updated"
        puts 'Common types: product.created, product.updated, price.created, price.updated'
      rescue Stripe::StripeError => ex
        puts "Error retrieving product events: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing products events', Onetime::CLI::BillingProductsEventsCommand

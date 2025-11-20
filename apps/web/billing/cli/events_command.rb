# apps/web/billing/cli/events_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # View recent Stripe events
    class BillingEventsCommand < Command
      include BillingHelpers

      desc 'View recent Stripe events'

      option :type, type: :string, desc: 'Filter by event type (e.g., customer.created, invoice.paid)'
      option :limit, type: :integer, default: 20, desc: 'Maximum results to return'

      def call(type: nil, limit: 20, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching recent events from Stripe...'
        params        = { limit: limit }
        params[:type] = type if type

        events = Stripe::Event.list(params)

        if events.data.empty?
          puts 'No events found'
          return
        end

        puts format('%-22s %-35s %s',
          'ID', 'TYPE', 'CREATED'
        )
        puts '-' * 70

        events.data.each do |event|
          puts format_event_row(event)
        end

        puts "\nTotal: #{events.data.size} event(s)"
        puts "\nCommon types: customer.created, customer.updated, invoice.paid,"
        puts '              subscription.created, subscription.updated, payment_intent.succeeded'
      rescue Stripe::StripeError => ex
        puts "Error fetching events: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing events', Onetime::CLI::BillingEventsCommand

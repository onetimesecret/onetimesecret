# apps/web/billing/cli/refunds_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List refunds
    class BillingRefundsCommand < Command
      include BillingHelpers

      desc 'List Stripe refunds'

      option :charge, type: :string, desc: 'Filter by charge ID'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(charge: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching refunds from Stripe...'
        params = { limit: limit }
        params[:charge] = charge if charge

        refunds = Stripe::Refund.list(params)

        if refunds.data.empty?
          puts 'No refunds found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'CHARGE', 'AMOUNT', 'STATUS', 'CREATED')
        puts '-' * 90

        refunds.data.each do |refund|
          amount = format_amount(refund.amount, refund.currency)
          created = format_timestamp(refund.created)

          puts format('%-22s %-22s %-12s %-10s %s',
            refund.id[0..21],
            refund.charge[0..21],
            amount[0..11],
            refund.status[0..9],
            created)
        end

        puts "\nTotal: #{refunds.data.size} refund(s)"

      rescue Stripe::StripeError => e
        puts "Error fetching refunds: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing refunds', Onetime::CLI::BillingRefundsCommand

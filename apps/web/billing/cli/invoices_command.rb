# apps/web/billing/cli/invoices_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe invoices
    class BillingInvoicesCommand < Command
      include BillingHelpers

      desc 'List Stripe invoices'

      option :status, type: :string, desc: 'Filter by status (draft, open, paid, uncollectible, void)'
      option :customer, type: :string, desc: 'Filter by customer ID'
      option :subscription, type: :string, desc: 'Filter by subscription ID'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(status: nil, customer: nil, subscription: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching invoices from Stripe...'
        params = { limit: limit }
        params[:status] = status if status
        params[:customer] = customer if customer
        params[:subscription] = subscription if subscription

        invoices = Stripe::Invoice.list(params)

        if invoices.data.empty?
          puts 'No invoices found'
          return
        end

        puts format('%-22s %-22s %-12s %-10s %s',
          'ID', 'CUSTOMER', 'AMOUNT', 'STATUS', 'CREATED')
        puts '-' * 80

        invoices.data.each do |invoice|
          puts format_invoice_row(invoice)
        end

        puts "\nTotal: #{invoices.data.size} invoice(s)"
        puts "\nStatuses: draft, open, paid, uncollectible, void"
      rescue Stripe::StripeError => e
        puts "Error fetching invoices: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing invoices', Onetime::CLI::BillingInvoicesCommand

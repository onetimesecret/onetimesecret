# apps/web/billing/cli/catalog_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # List Stripe customers
    class BillingCustomersCommand < Command
      include BillingHelpers

      desc 'List Stripe customers'

      option :email, type: :string, desc: 'Filter by email address'
      option :limit, type: :integer, default: 100, desc: 'Maximum results to return'

      def call(email: nil, limit: 100, **)
        boot_application!

        return unless stripe_configured?

        puts 'Fetching customers from Stripe...'
        params = { limit: limit }
        params[:email] = email if email

        customers = Stripe::Customer.list(params)

        if customers.data.empty?
          puts 'No customers found'
          return
        end

        puts format('%-22s %-30s %-25s %s',
          'ID', 'EMAIL', 'NAME', 'CREATED')
        puts '-' * 90

        customers.data.each do |customer|
          puts format_customer_row(customer)
        end

        puts "\nTotal: #{customers.data.size} customer(s)"
      rescue Stripe::StripeError => e
        puts "Error fetching customers: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing customers', Onetime::CLI::BillingCustomersCommand

# apps/web/billing/cli/customers_create_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create customer
    class BillingCustomersCreateCommand < Command
      include BillingHelpers

      desc 'Create a new Stripe customer'

      option :email, type: :string, desc: 'Customer email'
      option :name, type: :string, desc: 'Customer name'
      option :interactive, type: :boolean, default: false,
        desc: 'Interactive mode - prompt for fields'

      def call(email: nil, name: nil, interactive: false, **)
        boot_application!

        return unless stripe_configured?

        if interactive || email.nil?
          print 'Email: '
          email = $stdin.gets.chomp
          print 'Name (optional): '
          name  = $stdin.gets.chomp
        end

        if email.to_s.strip.empty?
          puts 'Error: Email is required'
          return
        end

        puts "\nCreating customer:"
        puts "  Email: #{email}"
        puts "  Name: #{name}" if name && !name.empty?

        print "\nProceed? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        customer_params        = { email: email }
        customer_params[:name] = name if name && !name.empty?

        # Use StripeClient for automatic retry and idempotency
        require_relative '../lib/stripe_client'
        stripe_client = Billing::StripeClient.new
        customer = stripe_client.create(Stripe::Customer, customer_params)

        puts "\nCustomer created successfully:"
        puts "  ID: #{customer.id}"
        puts "  Email: #{customer.email}"
        puts "  Name: #{customer.name}" if customer.name
      rescue Stripe::StripeError => ex
        puts format_stripe_error('Failed to create customer', ex)
      end
    end
  end
end

Onetime::CLI.register 'billing customers create', Onetime::CLI::BillingCustomersCreateCommand

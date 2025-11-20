# apps/web/billing/cli/refunds_create_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Create refund
    class BillingRefundsCreateCommand < Command
      include BillingHelpers

      desc 'Create a refund for a charge'

      option :charge, type: :string, required: true,
        desc: 'Charge ID (ch_xxx)'
      option :amount, type: :integer,
        desc: 'Amount in cents (leave empty for full refund)'
      option :reason, type: :string,
        desc: 'Reason: duplicate, fraudulent, requested_by_customer'
      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(charge:, amount: nil, reason: nil, yes: false, **)
        boot_application!

        return unless stripe_configured?

        charge_obj = Stripe::Charge.retrieve(charge)

        puts "Charge: #{charge_obj.id}"
        puts "Amount: #{format_amount(charge_obj.amount, charge_obj.currency)}"
        puts "Customer: #{charge_obj.customer}"
        puts

        refund_amount = amount || charge_obj.amount
        puts "Refund amount: #{format_amount(refund_amount, charge_obj.currency)}"
        puts "Reason: #{reason}" if reason

        unless yes
          print '\nCreate refund? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        refund_params = { charge: charge }
        refund_params[:amount] = amount if amount
        refund_params[:reason] = reason if reason

        refund = Stripe::Refund.create(refund_params)

        puts "\nRefund created successfully:"
        puts "  ID: #{refund.id}"
        puts "  Amount: #{format_amount(refund.amount, refund.currency)}"
        puts "  Status: #{refund.status}"

      rescue Stripe::StripeError => e
        puts "Error creating refund: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing refunds create', Onetime::CLI::BillingRefundsCreateCommand

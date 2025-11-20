# apps/web/billing/cli/payment_links_update_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Update payment link
    class BillingPaymentLinksUpdateCommand < Command
      include BillingHelpers

      desc 'Update a payment link'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      option :active, type: :boolean, desc: 'Activate or deactivate link'

      def call(link_id:, active: nil, **)
        boot_application!

        return unless stripe_configured?

        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment link: #{link.id}"
        puts "Current status: #{link.active ? 'active' : 'inactive'}"
        puts

        if active.nil?
          puts 'Error: Must specify --active true or --active false'
          return
        end

        status_word = active ? 'active' : 'inactive'
        print "Update status to #{status_word}? (y/n): "
        return unless $stdin.gets.chomp.downcase == 'y'

        updated = Stripe::PaymentLink.update(link_id, { active: active })

        puts "\nPayment link updated successfully"
        puts "Status: #{updated.active ? 'active' : 'inactive'}"

      rescue Stripe::StripeError => e
        puts "Error updating payment link: #{e.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing payment-links update', Onetime::CLI::BillingPaymentLinksUpdateCommand

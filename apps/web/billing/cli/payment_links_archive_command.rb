# apps/web/billing/cli/payment_links_archive_command.rb
#
# frozen_string_literal: true

require_relative 'helpers'

module Onetime
  module CLI
    # Archive payment link
    class BillingPaymentLinksArchiveCommand < Command
      include BillingHelpers

      desc 'Archive a payment link'

      argument :link_id, required: true, desc: 'Payment link ID (plink_xxx)'

      option :yes, type: :boolean, default: false,
        desc: 'Assume yes to prompts'

      def call(link_id:, yes: false, **)
        boot_application!

        return unless stripe_configured?

        link = Stripe::PaymentLink.retrieve(link_id)

        puts "Payment link: #{link.id}"
        puts "URL: #{link.url}"
        puts "Status: #{link.active ? 'active' : 'inactive'}"
        puts

        unless yes
          print 'Archive this payment link? (y/n): '
          return unless $stdin.gets.chomp.downcase == 'y'
        end

        Stripe::PaymentLink.update(link_id, { active: false })

        puts "\nPayment link archived successfully"
        puts 'Status: inactive'
        puts 'URL no longer accepts payments'
      rescue Stripe::StripeError => ex
        puts "Error archiving payment link: #{ex.message}"
      end
    end
  end
end

Onetime::CLI.register 'billing payment-links archive', Onetime::CLI::BillingPaymentLinksArchiveCommand

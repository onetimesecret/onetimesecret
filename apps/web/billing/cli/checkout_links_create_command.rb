# apps/web/billing/cli/checkout_links_create_command.rb
#
# frozen_string_literal: true

# Create a Stripe Checkout Session ("checkout link") for a specific customer.
#
# Thin adapter over Billing::Operations::CreateCheckoutLink (the single
# implementation, shared with the colonel POST /users/:user_id/checkout-link
# endpoint). This command owns CLI concerns only: identifier resolution,
# option parsing, and output formatting. The op creates the session AND
# records the ColonelAuditEvent.
#
# Usage:
#   bin/ots billing checkout-links create user@example.com --plan identity_plus_v1
#   bin/ots billing checkout-links create ur1234567890 --plan identity_plus_v1 --cycle yearly
#   bin/ots billing checkout-links create user@example.com --plan identity_plus_v1 --dry-run
#   bin/ots billing checkout-links create user@example.com --plan identity_plus_v1 --json

require 'json'

require_relative 'helpers'
require_relative '../operations/create_checkout_link'

module Onetime
  module CLI
    # Create a support-issued checkout link for a customer
    class BillingCheckoutLinksCreateCommand < Command
      include BillingHelpers

      desc 'Create a Stripe Checkout link for a specific customer'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email or extid of the customer'

      option :plan, type: :string, required: true, desc: "Plan family ID (e.g. 'identity_plus_v1')"
      option :cycle, type: :string, default: 'monthly', desc: 'Billing cycle: monthly or yearly'
      option :promo_codes, type: :boolean, default: false, desc: 'Allow promotion codes at checkout'
      option :dry_run, type: :boolean, default: false, desc: 'Resolve plan/price only; no Stripe call'
      option :json, type: :boolean, default: false, desc: 'Output as JSON'

      def call(identifier:, plan:, cycle: 'monthly', promo_codes: false,
               dry_run: false, json: false, **)
        boot_application!

        customer = Onetime::Customer.load_by_extid_or_email(identifier) ||
                   Onetime::Customer.load(identifier)
        unless customer&.exists?
          error_exit("Customer not found: #{identifier}", json: json)
        end

        org = ::Billing::Operations::CreateCheckoutLink.default_org_for(customer)
        unless org
          error_exit("Customer has no organization: #{identifier}", json: json)
        end

        result = ::Billing::Operations::CreateCheckoutLink.call(
          customer: customer,
          org: org,
          product: plan,
          interval: cycle,
          actor: "cli:#{ENV['USER'] || 'unknown'}",
          allow_promotion_codes: promo_codes,
          dry_run: dry_run,
        )

        if result.failed?
          error_exit(result.reason, json: json)
        end

        if json
          puts JSON.pretty_generate(serializable(result))
        else
          output_text(result, customer, org)
        end
      end

      private

      def serializable(result)
        {
          status: result.status,
          checkout_url: result.url,
          session_id: result.session_id,
          plan_id: result.plan_id,
          price_id: result.price_id,
          expires_at: result.expires_at,
        }
      end

      def output_text(result, customer, org)
        if result.would_create?
          puts 'Dry run — no checkout session created.'
          puts "  Customer: #{customer.extid} (#{customer.obscure_email})"
          puts "  Org:      #{org.extid}"
          puts "  Plan:     #{result.plan_id}"
          puts "  Price:    #{result.price_id}"
          return
        end

        puts 'Checkout link created:'
        puts "  Customer:   #{customer.extid} (#{customer.obscure_email})"
        puts "  Org:        #{org.extid}"
        puts "  Plan:       #{result.plan_id}"
        puts "  Price:      #{result.price_id}"
        puts "  Session:    #{result.session_id}"
        puts "  Expires:    #{Time.at(result.expires_at).utc.strftime('%Y-%m-%d %H:%M:%S UTC')}"
        puts
        puts "  URL: #{result.url}"
        puts
        puts 'Share this link with the customer. It expires 24 hours after creation.'
      end

      def error_exit(message, json: false)
        if json
          puts JSON.generate({ error: message })
        else
          puts "Error: #{message}"
        end
        exit 1
      end
    end
  end
end

Onetime::CLI.register 'billing checkout-links create', Onetime::CLI::BillingCheckoutLinksCreateCommand

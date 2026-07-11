# lib/onetime/cli/customers/show_command.rb
#
# frozen_string_literal: true

# Show detailed customer information by email, extid, or Rodauth account ID.
#
# Usage:
#   bin/ots customers show user@example.com          # Lookup by email
#   bin/ots customers show ur1234567890abcdef        # Lookup by extid
#   bin/ots customers show 123                       # Lookup by Rodauth account ID (full mode)
#   bin/ots customers show user@example.com --full   # Show unobscured email
#   bin/ots customers show user@example.com --json   # JSON output

require 'json'

# Customer resolution + organization detail are delegated to the shared
# Auth::Operations::Customers::Show op (single implementation); this command owns
# CLI concerns (identifier parsing, Rodauth account-id cross-reference, output
# formatting). The CLI runs outside the auth autoloader, so require it explicitly.
require 'auth/operations/customers/show'

module Onetime
  module CLI
    class CustomersShowCommand < Command
      include Customers::Shared

      desc 'Show detailed customer information'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, or Rodauth account ID of the customer'

      option :full,
        type: :boolean,
        default: false,
        desc: 'Show unobscured email address'

      option :json,
        type: :boolean,
        default: false,
        desc: 'Output as JSON'

      def call(identifier:, full: false, json: false, **)
        boot_application!

        if identifier.to_s.strip.empty?
          error_exit('Identifier is required', json: json)
          return
        end

        # resolve_customer keeps the CLI-specific numeric Rodauth-account-id
        # lookup; the Show op provides the found?/organizations detail.
        result = Auth::Operations::Customers::Show.new(
          customer: resolve_customer(identifier),
        ).call

        unless result.found?
          error_exit("Customer not found: #{identifier}", json: json)
          return
        end

        customer = result.customer

        # lookup_account_id returns nil in simple mode (no SQL DB) and
        # nil in full mode when the Customer has no linked accounts row.
        account_id = lookup_account_id(customer)

        if json
          output_json(customer, full: full, account_id: account_id, organizations: result.organizations)
        else
          output_text(customer, full: full, account_id: account_id, organizations: result.organizations)
        end
      end

      private

      def output_text(customer, full:, account_id:, organizations:)
        email_display = full ? customer.email : customer.obscure_email
        orgs          = organizations

        puts 'Customer Details'
        puts '-' * 40
        puts format('  %-18s %s', 'extid:', customer.extid)
        puts format('  %-18s %s', 'objid:', customer.objid)
        puts format('  %-18s %s', 'custid:', customer.custid)
        puts format('  %-18s %s', 'email:', email_display)
        puts format('  %-18s %s', 'role:', customer.role)
        puts format('  %-18s %s', 'planid:', customer.planid.to_s.empty? ? '(none)' : customer.planid)
        puts format('  %-18s %s', 'locale:', customer.locale.to_s.empty? ? '(default)' : customer.locale)
        puts format('  %-18s %s', 'verified:', customer.verified?)
        puts format('  %-18s %s', 'created:', format_timestamp(customer.created))
        puts format('  %-18s %s', 'default_org_id:', customer.default_org_id.to_s.empty? ? '(none)' : customer.default_org_id)
        # Only displayed in full auth mode (lookup_account_id returns nil
        # otherwise); useful for cross-referencing against the Rodauth
        # accounts table in admin queries.
        puts format('  %-18s %s', 'rodauth_account_id:', account_id) if account_id

        puts
        puts 'Organizations'
        puts '-' * 40
        if orgs.empty?
          puts '  (none)'
        else
          orgs.each do |org|
            next unless org

            puts format('  - %s (%s)', org[:display_name] || org[:objid], org[:objid])
          end
        end
      end

      def output_json(customer, full:, account_id:, organizations:)
        orgs = organizations

        data = {
          extid: customer.extid,
          objid: customer.objid,
          custid: customer.custid,
          email: full ? customer.email : customer.obscure_email,
          role: customer.role,
          planid: customer.planid,
          locale: customer.locale,
          verified: customer.verified?,
          created: customer.created.to_f,
          created_formatted: format_timestamp(customer.created),
          default_org_id: customer.default_org_id,
          rodauth_account_id: account_id,
          organizations: orgs,
        }

        puts JSON.pretty_generate(data)
      end

      def format_timestamp(ts)
        return '(unknown)' if ts.nil? || ts.to_f <= 0

        Time.at(ts.to_f).utc.strftime('%Y-%m-%d %H:%M:%S UTC')
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

    register 'customers show', CustomersShowCommand
  end
end

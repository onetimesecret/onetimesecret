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

        customer = resolve_customer(identifier)

        unless customer
          error_exit("Customer not found: #{identifier}", json: json)
          return
        end

        # lookup_account_id returns nil in simple mode (no SQL DB) and
        # nil in full mode when the Customer has no linked accounts row.
        account_id = lookup_account_id(customer)

        if json
          output_json(customer, full: full, account_id: account_id)
        else
          output_text(customer, full: full, account_id: account_id)
        end
      end

      private

      def output_text(customer, full:, account_id:)
        email_display = full ? customer.email : customer.obscure_email
        orgs          = customer.organization_instances.to_a

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

            puts format('  - %s (%s)', org.display_name || org.objid, org.objid)
          end
        end
      end

      def output_json(customer, full:, account_id:)
        orgs = customer.organization_instances.to_a.compact.map do |org|
          {
            objid: org.objid,
            extid: org.extid,
            display_name: org.display_name,
          }
        end

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

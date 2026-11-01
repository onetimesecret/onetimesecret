# lib/onetime/cli/customers/show_command.rb
#
# frozen_string_literal: true

# Show detailed customer information by email, extid, objid, or Rodauth
# account ID.
#
# Usage:
#   bin/ots customers show user@example.com          # Lookup by email
#   bin/ots customers show ur1234567890abcdef        # Lookup by extid
#   bin/ots customers show 0199d3c4-5b6a-...         # Lookup by objid
#   bin/ots customers show 123                       # Lookup by Rodauth account ID (full mode)
#   bin/ots customers show user@example.com --full   # Show unobscured email
#   bin/ots customers show user@example.com --json   # JSON output

require 'json'

# Customer resolution + organization detail are delegated to the shared
# Auth::Operations::Customers::Show op (single implementation); this command owns
# CLI concerns (identifier parsing, Rodauth account-id cross-reference, output
# formatting). The CLI runs outside the auth autoloader, so require it explicitly.
require 'auth/operations/customers/show'

# Customers::Shared must exist before `include Customers::Shared` below.
# Required here (not only from the lib/onetime/cli.rb manifest) so this file
# cannot be loaded in a broken order.
require_relative 'shared'

module Onetime
  module CLI
    class CustomersShowCommand < Command
      include Customers::Shared

      desc 'Show detailed customer information'

      argument :identifier,
        type: :string,
        required: true,
        desc: 'Email, extid, objid, or Rodauth account ID of the customer'

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

        render = json ? method(:output_json) : method(:output_text)
        render.call(
          customer,
          full: full,
          account_id: account_id,
          organizations: result.organizations,
          rodauth_admin_url: result.rodauth_admin_url,
        )
      end

      private

      def output_text(customer, full:, account_id:, organizations:, rodauth_admin_url: nil)
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
        puts format('  %-18s %s', 'default_org:', default_org_label(customer, orgs))
        # Only displayed in full auth mode (lookup_account_id returns nil
        # otherwise); useful for cross-referencing against the Rodauth
        # accounts table in admin queries.
        puts format('  %-18s %s', 'rodauth_account_id:', account_id) if account_id
        # Deep link into the standalone Rodauth Admin (RODAUTH_ADMIN_URL);
        # absent when unset or not in full auth mode.
        puts format('  %-18s %s', 'rodauth_admin:', rodauth_admin_url) if rodauth_admin_url

        puts
        puts 'Organizations'
        puts '-' * 40
        if orgs.empty?
          puts '  (none)'
        else
          orgs.each do |org|
            next unless org

            default = org[:objid].to_s == customer.default_org_id.to_s ? '  [default]' : ''
            puts format('  - %s (%s)%s', org[:extid], org[:display_name], default)
          end
        end
      end

      def output_json(customer, full:, account_id:, organizations:, rodauth_admin_url: nil)
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
          default_org_extid: default_org_extid(customer, orgs),
          rodauth_account_id: account_id,
          rodauth_admin_url: rodauth_admin_url,
          organizations: orgs,
        }

        puts JSON.pretty_generate(data)
      end

      # The default org by PUBLIC id, with the stored objid alongside for
      # Redis debugging. Read from the membership list when it is there; a
      # default pointing outside it (or at a deleted org) still shows the objid.
      def default_org_label(customer, orgs)
        objid = customer.default_org_id.to_s
        return '(none)' if objid.empty?

        "#{default_org_extid(customer, orgs) || '(not found)'} (#{objid})"
      end

      def default_org_extid(customer, orgs)
        objid = customer.default_org_id.to_s
        return nil if objid.empty?

        match = orgs.compact.find { |org| org[:objid].to_s == objid }
        match ? match[:extid] : Onetime::Organization.load(objid)&.extid
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

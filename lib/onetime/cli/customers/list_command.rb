# lib/onetime/cli/customers/list_command.rb
#
# frozen_string_literal: true

# List all customers grouped by email domain.
#
# Usage:
#   bin/ots customers list                    # List grouped by custid domain
#   bin/ots customers list --by-email         # List grouped by email domain
#
# Customer enumeration is delegated to the shared Auth::Operations::Customers::List
# op (single implementation, shared with the colonel API); this command owns only
# the domain-grouping presentation. The CLI runs outside the auth autoloader, so
# require the op explicitly.
require 'auth/operations/customers/list'

module Onetime
  module CLI
    class CustomersListCommand < Command
      desc 'List all customers grouped by domain'

      option :by_email,
        type: :boolean,
        default: false,
        desc: 'Group by email domain instead of custid'

      def call(by_email: false, **)
        boot_application!

        puts format('%d customers', Onetime::Customer.instances.size)

        # per_page: :all loads every customer in one shot — acceptable here
        # because this is an off-request operational CLI grouping view (not a
        # request handler). The grouping below is order-independent.
        all_customers = Auth::Operations::Customers::List.new(per_page: :all).call.customers

        # Choose the field to group by
        field = by_email ? :email : :custid

        # Group customers by the domain portion of the email address
        grouped_customers = all_customers.group_by do |cust|
          next if cust.nil?

          email  = cust.send(field).to_s
          domain = email.split('@')[1] || 'unknown'
          domain
        end

        # Sort the grouped customers by domain
        grouped_customers.sort_by { |_, customers| customers.size }.each do |domain, customers|
          puts "#{domain} #{customers.size}"
        end
      end
    end

    register 'customers list', CustomersListCommand
  end
end

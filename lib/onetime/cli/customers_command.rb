# lib/onetime/cli/customers_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    class CustomersCommand < Command
      desc 'List and check customer records'

      option :list, type: :boolean, default: false,
        desc: 'List all customers grouped by domain'

      option :check, type: :boolean, default: false,
        desc: 'Check for customers with mismatched custid and email fields'

      option :check_email, type: :boolean, default: false,
        desc: 'When listing, group by email domain instead of custid'

      def call(list: false, check: false, check_email: false, **)
        boot_application!

        puts format('%d customers', Onetime::Customer.instances.size)

        if list
          all_customers = Onetime::Customer.instances.all.map do |custid|
            Onetime::Customer.load(custid)
          end

          # Choose the field to group by
          field = check_email ? :email : :custid

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

        elsif check
          all_customers = Onetime::Customer.instances.all.map do |custid|
            Onetime::Customer.load(custid)
          end

          mismatched_customers = all_customers.select do |cust|
            next if cust.nil?

            custid_email = cust.custid.to_s
            email_field  = cust.email.to_s
            custid_email != email_field
          end

          if mismatched_customers.empty?
            puts 'All customers have matching custid and email fields.'
          end

          mismatched_customers.each do |cust|
            next if cust.nil?

            obscured_custid = OT::Utils.obscure_email(cust.custid)
            obscured_email  = OT::Utils.obscure_email(cust.email)
            puts "CustID and email mismatch: CustID: #{obscured_custid}, Email: #{obscured_email}"
          end
        end
      end
    end

    register 'customers', CustomersCommand
  end
end

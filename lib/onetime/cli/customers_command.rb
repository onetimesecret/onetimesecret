# lib/onetime/cli/customers_command.rb

module Onetime
  class CustomersCommand < Drydock::Command
    def customers
      puts format('%d customers', V2::Customer.values.size)
      if option.list
        all_customers = V2::Customer.values.all.map do |custid|
          V2::Customer.load(custid)
        end

        # Choose the field to group by
        field = option.check_email ? :email : :custid

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

      elsif option.check
        all_customers = V2::Customer.values.all.map do |custid|
          V2::Customer.load(custid)
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
          obscured_custid = OT::Utils.obscure_email(cust.custid)
          obscured_email  = OT::Utils.obscure_email(cust.email)
          puts "CustID and email mismatch: CustID: #{obscured_custid}, Email: #{obscured_email}"
        end
      end
    end
  end
end

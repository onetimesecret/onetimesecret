# lib/onetime/cli/customers_command.rb
#
# CLI command for managing customer records including creation, listing, and validation.
#
# Usage:
#   bin/ots customers --list                           # List all customers
#   bin/ots customers --create user@example.com        # Create customer with default role
#   bin/ots customers --create user@example.com --role colonel  # Create admin
#   bin/ots customers --check                          # Check for mismatches
#
# frozen_string_literal: true

module Onetime
  module CLI
    class CustomersCommand < Command
      desc 'Manage customer records (create, list, check)'

      option :list, type: :boolean, default: false,
        desc: 'List all customers grouped by domain'

      option :check, type: :boolean, default: false,
        desc: 'Check for customers with mismatched custid and email fields'

      option :check_email, type: :boolean, default: false,
        desc: 'When listing, group by email domain instead of custid'

      option :create, type: :string, default: nil,
        desc: 'Create a new customer with the specified email address'

      option :role, type: :string, default: 'customer',
        desc: 'Role for new customer (customer, colonel, admin, staff)'

      option :password, type: :string, default: nil,
        desc: 'Password for new customer (generates random if not provided)'

      option :verified, type: :boolean, default: true,
        desc: 'Whether to mark the account as verified (default: true)'

      # Valid roles in hierarchy order
      VALID_ROLES = %w[colonel admin staff customer].freeze

      def call(list: false, check: false, check_email: false, create: nil, role: 'customer', password: nil, verified: true, **)
        boot_application!

        if create
          create_customer(create, role, password, verified)
        elsif list
          list_customers(check_email)
        elsif check
          check_customers
        else
          puts format('%d customers', Onetime::Customer.instances.size)
          puts "\nUsage:"
          puts '  bin/ots customers --list                    # List all customers'
          puts '  bin/ots customers --create EMAIL            # Create new customer'
          puts '  bin/ots customers --create EMAIL --role colonel  # Create admin'
          puts '  bin/ots customers --check                   # Check for mismatches'
        end
      end

      private

      def create_customer(email, role, password, verified)
        # Validate inputs
        unless valid_email?(email)
          puts "Error: Invalid email address: #{email}"
          exit 1
        end

        unless VALID_ROLES.include?(role)
          puts "Error: Invalid role '#{role}'. Valid roles: #{VALID_ROLES.join(', ')}"
          exit 1
        end

        # Check if customer already exists
        if Onetime::Customer.email_exists?(email)
          obscured = OT::Utils.obscure_email(email)
          puts "Error: Customer already exists: #{obscured}"
          puts "Use 'bin/ots role promote #{email}' to change their role."
          exit 1
        end

        # Generate password if not provided
        password ||= generate_secure_password
        obscured = OT::Utils.obscure_email(email)

        auth_mode = Onetime.auth_config.mode
        puts "Creating customer in #{auth_mode} auth mode..."

        case auth_mode
        when 'full'
          create_customer_full_mode(email, role, password, verified)
        when 'simple'
          create_customer_simple_mode(email, role, password, verified)
        else
          # Disabled mode - still allow Redis-only creation
          create_customer_simple_mode(email, role, password, verified)
        end

        puts
        puts "Customer created: #{obscured}"
        puts "Role: #{role}"
        puts "Verified: #{verified}"
        puts
        puts "Generated password: #{password}"
        puts
        puts 'Save this password - it will not be displayed again.'

        OT.info "[customer-create] #{obscured} role=#{role} verified=#{verified} auth_mode=#{auth_mode}"
      end

      # Simple mode: Redis-only customer creation
      def create_customer_simple_mode(email, role, password, verified)
        customer = Onetime::Customer.create!(
          email: email,
          role: role,
          verified: verified.to_s,
          verified_by: 'cli_provision',
        )

        customer.update_passphrase(password, algorithm: :argon2)
        customer.save

        customer
      end

      # Full mode: Redis + SQL account creation
      def create_customer_full_mode(email, role, password, verified)
        # Get auth database connection
        db = Auth::Database.connection
        unless db
          puts 'Error: Auth database not available.'
          puts 'Please ensure your database configuration is correct.'
          exit 1
        end

        # Create Redis customer first
        customer = Onetime::Customer.create!(
          email: email,
          role: role,
          verified: verified.to_s,
          verified_by: 'cli_provision',
        )
        customer.update_passphrase(password, algorithm: :argon2)
        customer.save

        # Create SQL account and link
        create_rodauth_account(db, email, password, customer.extid, verified)

        customer
      end

      # Create Rodauth account in SQL database
      def create_rodauth_account(db, email, password, external_id, verified)
        # Use Argon2 with same params as Rodauth config
        argon2_params = if ENV['RACK_ENV'] == 'test'
          { t_cost: 1, m_cost: 5, p_cost: 1 }
        else
          { t_cost: 2, m_cost: 16, p_cost: 1 }
        end

        argon2        = ::Argon2::Password.new(**argon2_params)
        password_hash = argon2.create(password)

        # status_id: 1=Unverified, 2=Verified (per Rodauth convention)
        status_id = verified ? 2 : 1

        # Insert into accounts table
        account_id = db[:accounts].insert(
          email: email,
          status_id: status_id,
          external_id: external_id,
          created_at: Time.now,
          updated_at: Time.now,
        )

        # Insert password hash into separate table (Rodauth's password storage pattern)
        db[:account_password_hashes].insert(
          id: account_id,
          password_hash: password_hash,
          created_at: Time.now,
        )

        account_id
      rescue Sequel::UniqueConstraintViolation => e
        puts "Error: Account already exists in auth database: #{e.message}"
        exit 1
      end

      def list_customers(check_email)
        puts format('%d customers', Onetime::Customer.instances.size)

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
      end

      def check_customers
        puts format('%d customers', Onetime::Customer.instances.size)

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
          return
        end

        mismatched_customers.each do |cust|
          next if cust.nil?

          obscured_custid = OT::Utils.obscure_email(cust.custid)
          obscured_email  = OT::Utils.obscure_email(cust.email)
          puts "CustID and email mismatch: CustID: #{obscured_custid}, Email: #{obscured_email}"
        end
      end

      # Generate cryptographically secure random password
      def generate_secure_password
        # 20 characters = ~119 bits entropy (log2(62^20))
        SecureRandom.alphanumeric(20)
      end

      # Basic email validation
      def valid_email?(email)
        return false if email.nil? || email.empty?

        # Simple regex for email validation
        email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      end
    end

    register 'customers', CustomersCommand
  end
end

# lib/onetime/cli/apitoken_command.rb
#
# frozen_string_literal: true

# CLI command for generating and displaying Basic Auth API credentials.
#
# Usage:
#   bin/ots apitoken user@example.com              # Regenerate token for existing customer
#   bin/ots apitoken user@example.com --create      # Create customer if needed, then generate token
#   bin/ots apitoken user@example.com --show        # Show existing token without regenerating
#

require 'base64'

module Onetime
  module CLI
    class ApiTokenCommand < Command
      desc 'Generate or display Basic Auth API credentials for a customer'

      argument :email, type: :string, required: true, desc: 'Customer email address'

      option :create,
        type: :boolean,
        default: false,
        desc: 'Create the customer if they do not exist'

      option :role,
        type: :string,
        default: 'customer',
        desc: 'Role for new customer (only applies with --create)'

      option :password,
        type: :string,
        default: nil,
        desc: 'Password for new account (generates random if not provided; full auth mode only)'

      option :verified,
        type: :boolean,
        default: true,
        desc: 'Whether to mark created accounts as verified (default: true)'

      option :show,
        type: :boolean,
        default: false,
        desc: 'Show existing token without regenerating'

      # Valid roles in hierarchy order
      VALID_ROLES = %w[colonel admin staff customer].freeze

      def call(email:, create: false, role: 'customer', password: nil, verified: true, show: false, **)
        boot_application!

        unless valid_email?(email)
          puts "Error: Invalid email address: #{email}"
          exit 1
        end

        customer = resolve_customer(email, create, role, password, verified)

        if show
          show_existing_token(customer, email)
        else
          regenerate_and_display(customer, email)
        end
      end

      private

      # Find an existing customer or create one if --create was given.
      def resolve_customer(email, create, role, password, verified)
        if Onetime::Customer.email_exists?(email)
          Onetime::Customer.find_by_email(email)
        elsif create
          create_customer(email, role, password, verified)
        else
          obscured = OT::Utils.obscure_email(email)
          puts "Error: Customer not found: #{obscured}"
          puts
          puts 'To create the customer and generate a token in one step:'
          puts "  bin/ots apitoken #{email} --create"
          puts
          puts 'Or create the customer first:'
          puts "  bin/ots customers --create #{email}"
          exit 1
        end
      end

      def show_existing_token(customer, email)
        token = customer.apitoken
        if token.to_s.empty?
          puts 'No API token exists for this customer.'
          puts "Run without --show to generate one:"
          puts "  bin/ots apitoken #{email}"
          exit 1
        end

        display_credentials(email, token)
      end

      def regenerate_and_display(customer, email)
        token = customer.regenerate_apitoken
        OT.info "[apitoken] Regenerated API token for #{OT::Utils.obscure_email(email)}"
        display_credentials(email, token)
      end

      def display_credentials(email, token)
        encoded = Base64.strict_encode64("#{email}:#{token}")
        base_url = site_host

        puts "API Token: #{token}"
        puts "Authorization: Basic #{encoded}"
        puts
        puts "curl -u '#{email}:#{token}' #{base_url}/api/v2/account"
        puts "curl -H 'Authorization: Basic #{encoded}' #{base_url}/api/v2/account"

        if billing_enabled?
          puts
          puts 'Note: Billing is enabled. This account has default (free tier) entitlements.'
        end
      end

      def create_customer(email, role, password, verified)
        unless VALID_ROLES.include?(role)
          puts "Error: Invalid role '#{role}'. Valid roles: #{VALID_ROLES.join(', ')}"
          exit 1
        end

        password ||= generate_secure_password
        auth_mode = Onetime.auth_config.mode
        puts "Creating customer in #{auth_mode} auth mode..."

        customer = case auth_mode
        when 'full'
          create_customer_full_mode(email, role, password, verified)
        else
          create_customer_simple_mode(email, role, password, verified)
        end

        puts "Customer created: #{OT::Utils.obscure_email(email)}"
        puts "Role: #{role}"
        puts "Verified: #{verified}"
        puts "Generated password: #{password}"
        puts
        OT.info "[apitoken] Created customer #{OT::Utils.obscure_email(email)} role=#{role} verified=#{verified} auth_mode=#{auth_mode}"

        customer
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
        db = Auth::Database.connection
        unless db
          puts 'Error: Auth database not available.'
          puts 'Please ensure your database configuration is correct.'
          exit 1
        end

        customer = Onetime::Customer.create!(
          email: email,
          role: role,
          verified: verified.to_s,
          verified_by: 'cli_provision',
        )
        customer.update_passphrase(password, algorithm: :argon2)
        customer.save

        begin
          create_rodauth_account(db, email, password, customer.extid, verified)
        rescue StandardError => ex
          customer.destroy!
          raise ex
        end

        customer
      end

      # Create Rodauth account in SQL database
      def create_rodauth_account(db, email, password, external_id, verified)
        argon2_params = if ENV['RACK_ENV'] == 'test'
          { t_cost: 1, m_cost: 5, p_cost: 1 }
        else
          { t_cost: 2, m_cost: 16, p_cost: 1 }
        end

        argon2        = ::Argon2::Password.new(**argon2_params)
        password_hash = argon2.create(password)

        status_id = verified ? 2 : 1

        account_id = db[:accounts].insert(
          email: email,
          status_id: status_id,
          external_id: external_id,
          created_at: Time.now,
          updated_at: Time.now,
        )

        db[:account_password_hashes].insert(
          id: account_id,
          password_hash: password_hash,
          created_at: Time.now,
        )

        account_id
      rescue Sequel::UniqueConstraintViolation => ex
        puts "Error: Account already exists in auth database: #{ex.message}"
        exit 1
      end

      def generate_secure_password
        SecureRandom.alphanumeric(20)
      end

      def valid_email?(email)
        return false if email.nil? || email.empty?

        email.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      end

      def site_host
        OT.conf&.dig(:site, :host) || 'https://localhost:3000'
      rescue StandardError
        'https://localhost:3000'
      end

      def billing_enabled?
        Onetime.billing_config&.enabled?
      rescue StandardError
        false
      end
    end

    register 'apitoken', ApiTokenCommand
  end
end

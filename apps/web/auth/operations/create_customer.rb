# apps/web/auth/operations/create_customer.rb
#
# frozen_string_literal: true

#
# Creates or loads a Customer record and links it to a Rodauth account.
# This operation is typically called after account creation.
#

module Auth
  module Operations
    class CreateCustomer
      include Onetime::LoggerMethods

      # @param account_id [Integer] The ID of the Rodauth account
      # @param account [Hash] The Rodauth account hash, containing at least :email
      # @param db [Sequel::Database] The database connection (optional)
      # @param provisioning_origin [String, nil] One of Onetime::Customer::PROVISIONING_ORIGINS.
      #   Set on newly-created Customer records as lifecycle/audit metadata.
      #   Ignored when the customer already exists (we don't rewrite history).
      # @param signup_domain_id [String, nil] CustomDomain identifier captured at signup.
      #   Set on newly-created Customer records. Ignored for existing customers to
      #   preserve original signup context (same "don't rewrite history" rule as
      #   provisioning_origin).
      def initialize(account_id:, account:, db: nil, provisioning_origin: nil, signup_domain_id: nil)
        @account_id          = account_id
        @account             = account
        @db                  = db || Auth::Database.connection
        @provisioning_origin = provisioning_origin
        @signup_domain_id    = signup_domain_id
      end

      # Executes the customer creation/loading operation
      # @return [Onetime::Customer] The created or existing customer
      def call
        customer = find_or_create_customer

        link_to_rodauth_account(customer)
        verify_link(customer)

        customer
      end

      private

      # Finds existing customer or creates a new one
      # @return [Onetime::Customer]
      def find_or_create_customer
        if Onetime::Customer.exists?(@account[:email])
          customer = Onetime::Customer.find_by_email(@account[:email])
          auth_logger.info "[create-customer] Found existing customer: #{customer.custid}"
        else
          # New accounts default to 'customer' role. Colonel promotion
          # is handled exclusively via CLI: bin/ots customers role promote user@example.com
          customer = Onetime::Customer.create!(
            email: @account[:email],
            role: 'customer',
            verified: false, # needs to be updated in after_verify_account
            provisioning_origin: @provisioning_origin,
            signup_domain_id: @signup_domain_id,
          )

          auth_logger.info "[create-customer] Created new customer: #{customer.custid} (role: customer, origin: #{@provisioning_origin || 'unknown'}, signup_domain_id: #{@signup_domain_id || 'none'})"
        end

        customer
      end

      # Links the customer to the Rodauth account via external_id
      # @param customer [Onetime::Customer]
      def link_to_rodauth_account(customer)
        rows_updated = @db[:accounts]
          .where(id: @account_id)
          .update(external_id: customer.extid)
        auth_logger.info "[create-customer] Linked Rodauth account #{@account_id} to extid: #{customer.extid} (rows_updated: #{rows_updated})"
      end

      # Verifies the link was created successfully
      # @param customer [Onetime::Customer]
      def verify_link(customer)
        stored_extid = @db[:accounts]
          .where(id: @account_id)
          .get(:external_id)

        auth_logger.info "[create-customer] Verification - stored external_id: #{stored_extid}"

        unless stored_extid == customer.extid
          OT.le "[create-customer] WARNING: external_id mismatch! Expected #{customer.extid}, got #{stored_extid}"
        end
      end
    end
  end
end

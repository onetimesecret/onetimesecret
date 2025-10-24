# apps/web/auth/operations/create_customer.rb

#
# Creates or loads a Customer record and links it to a Rodauth account.
# This operation is typically called after account creation.
#

module Auth
  module Operations
    class CreateCustomer
      # @param account_id [Integer] The ID of the Rodauth account
      # @param account [Hash] The Rodauth account hash, containing at least :email
      # @param db [Sequel::Database] The database connection (optional)
      def initialize(account_id:, account:, db: nil)
        @account_id = account_id
        @account = account
        @db = db || Auth::Config::Database.connection
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
          OT.info "[create-customer] Found existing customer: #{customer.custid}"
        else
          customer = Onetime::Customer.create!(
            email: @account[:email],
            role: 'customer',
            verified: '1'
          )
          OT.info "[create-customer] Created new customer: #{customer.custid}"
        end

        customer
      end

      # Links the customer to the Rodauth account via external_id
      # @param customer [Onetime::Customer]
      def link_to_rodauth_account(customer)
        rows_updated = @db[:accounts]
          .where(id: @account_id)
          .update(external_id: customer.extid)

        OT.info "[create-customer] Linked Rodauth account #{@account_id} to extid: #{customer.extid} (rows_updated: #{rows_updated})"
      end

      # Verifies the link was created successfully
      # @param customer [Onetime::Customer]
      def verify_link(customer)
        stored_extid = @db[:accounts]
          .where(id: @account_id)
          .get(:external_id)

        OT.info "[create-customer] Verification - stored external_id: #{stored_extid}"

        unless stored_extid == customer.extid
          OT.le "[create-customer] WARNING: external_id mismatch! Expected #{customer.extid}, got #{stored_extid}"
        end
      end
    end
  end
end

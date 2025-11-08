# apps/web/auth/operations/verify_customer.rb
#
# frozen_string_literal: true

#
# Updates the Customer's verification status when the Rodauth account is verified.
# This operation is typically called at the end of the sign up flow.
#

module Auth
  module Operations
    class VerifyCustomer
      # @param account [Hash] The Rodauth account hash, containing :external_id
      def initialize(account:)
        @account = account
      end

      # Executes the customer verification operation
      # @return [Boolean] true if successful, false if customer not found
      def call
        return false unless @account[:external_id]

        customer = find_customer
        return false unless customer

        verify_customer(customer)
        true
      end

      private

      # Finds the customer by external_id
      # @return [Onetime::Customer, nil]
      def find_customer
        customer = Onetime::Customer.find_by_extid(@account[:external_id])

        if customer.nil?
          OT.info "[verify-customer] Customer not found for extid: #{@account[:external_id]}"
        end

        customer
      end

      # Updates the customer's verified status
      # @param customer [Onetime::Customer]
      def verify_customer(customer)
        customer.verified = true
        customer.save

        OT.info "[verify-customer] Verified customer: #{customer.custid}"
      end
    end
  end
end

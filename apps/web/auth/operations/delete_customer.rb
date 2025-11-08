# apps/web/auth/operations/delete_customer.rb
#
# frozen_string_literal: true

#
# Deletes the Customer record associated with a closed Rodauth account.
# This operation is typically called after account closure.
#

module Auth
  module Operations
    class DeleteCustomer
      # @param account [Hash] The Rodauth account hash, containing :external_id
      def initialize(account:)
        @account = account
      end

      # Executes the customer deletion operation
      # @return [Boolean] true if successful, false if customer not found
      def call
        return false unless @account[:external_id]

        customer = find_customer
        return false unless customer

        delete_customer(customer)
        true
      end

      private

      # Finds the customer by external_id
      # @return [Onetime::Customer, nil]
      def find_customer
        customer = Onetime::Customer.find_by_extid(@account[:external_id])

        if customer.nil?
          OT.info "[delete-customer] Customer not found for extid: #{@account[:external_id]}"
        end

        customer
      end

      # Deletes the customer record
      # @param customer [Onetime::Customer]
      def delete_customer(customer)
        custid = customer.custid
        extid = customer.extid

        customer.destroy!

        OT.info "[delete-customer] Deleted customer: #{custid} (extid: #{extid})"
      end
    end
  end
end

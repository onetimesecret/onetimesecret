# apps/web/auth/operations/update_password_metadata.rb
#
# frozen_string_literal: true

#
# Updates customer metadata after a password change.
# This operation syncs password change timestamp from Rodauth to the Customer model.
#

module Auth
  module Operations
    class UpdatePasswordMetadata
      # @param account [Hash] The Rodauth account hash, containing :external_id
      def initialize(account:)
        @account = account
      end

      # Executes the password metadata update
      # @return [Boolean] true if successful, false if customer not found
      def call
        return false unless @account[:external_id]

        customer = find_customer
        return false unless customer

        update_customer_metadata(customer)
        true
      end

      private

      # Finds the customer by external_id
      # @return [Onetime::Customer, nil]
      def find_customer
        customer = Onetime::Customer.find_by_extid(@account[:external_id])

        if customer.nil?
          OT.info "[update-password-metadata] Customer not found for extid: #{@account[:external_id]}"
        end

        customer
      end

      # Updates the customer's password metadata
      # @param customer [Onetime::Customer]
      def update_customer_metadata(customer)
        customer.passphrase_updated = Familia.now.to_i
        customer.save

        OT.info "[update-password-metadata] Updated password metadata for customer: #{customer.custid}"
      end
    end
  end
end

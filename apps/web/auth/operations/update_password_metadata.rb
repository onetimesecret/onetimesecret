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
      #   and :email
      def initialize(account:)
        @account = account
      end

      # Executes the password metadata update
      # @return [Boolean] true if successful, false if customer not found
      def call
        customer = find_customer
        return false unless customer

        update_customer_metadata(customer)
        true
      end

      private

      # Resolve the customer the same way the password hooks and
      # RevokeAllForCustomerExceptCurrent do: external_id first, falling back to
      # the account email (Customer.load_by_extid_or_email handles both).
      # external_id is nullable in the accounts schema, so a bare extid-only
      # lookup would silently skip the watermark stamp for those accounts — and
      # the async sweep (#3810) would then run unguarded and kill the
      # just-rotated session.
      # @return [Onetime::Customer, nil]
      def find_customer
        identifier = @account[:external_id].to_s.empty? ? @account[:email] : @account[:external_id]
        return nil if identifier.to_s.strip.empty?

        customer = Onetime::Customer.load_by_extid_or_email(identifier)

        if customer.nil?
          OT.info "[update-password-metadata] Customer not found for: #{identifier}"
        end

        customer
      end

      # Updates the customer's password metadata
      # @param customer [Onetime::Customer]
      def update_customer_metadata(customer)
        customer.last_password_update! Familia.now.to_i # use fast-writer for just this field

        OT.info "[update-password-metadata] Updated password metadata for customer: #{customer.extid}"
      end
    end
  end
end

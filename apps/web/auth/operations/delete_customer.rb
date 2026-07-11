# apps/web/auth/operations/delete_customer.rb
#
# frozen_string_literal: true

#
# Deletes a Customer record. The single delete primitive for the customer
# domain, used by:
#   - account closure (passes the Rodauth `account:` hash)
#   - admin purge, both the colonel endpoint and `bin/ots customers purge`
#     (pass a pre-resolved `customer:`, wrapped by Auth::Operations::Customers::Purge
#     which adds the admin audit event)
#
# It performs no audit itself — auditing is an admin-context concern layered on
# top by Customers::Purge, so the plain account-closure path stays audit-free.
#

module Auth
  module Operations
    class DeleteCustomer
      # Redis sub-keys that make up a customer, for the raw-key delete path used
      # when purging directly against a foreign Redis (e.g. a pre-migration db via
      # `--redis-url`) where Familia models and their indexes are not available.
      # Owned here so there is one authoritative list (folded from the former CLI
      # copy in customers/purge_command.rb).
      CUSTOMER_SUB_KEYS = %w[object metadata receipts reset_secret
                             pending_email_change pending_email_delivery_status
                             feature_flags].freeze

      # @param account [Hash, nil] Rodauth account hash containing :external_id
      #   (account-closure path)
      # @param customer [Onetime::Customer, nil] a pre-resolved customer to delete
      #   (admin purge path). Takes precedence over account.
      def initialize(account: nil, customer: nil)
        @account  = account
        @customer = customer
      end

      # Executes the customer deletion.
      # @return [Boolean] true if a customer was deleted, false if none was found
      def call
        customer = @customer || find_by_account
        return false unless customer

        delete_customer(customer)
        true
      end

      # Delete a customer's Redis keys directly on the given client, without
      # loading a model or cleaning class-level indexes. Used only for the
      # `--redis-url` foreign-Redis purge path where indexes are being abandoned
      # wholesale. DEL silently ignores missing keys.
      #
      # @param dbclient the Redis/Valkey client to delete against
      # @param objid [String] the customer's objid
      # @return [Integer] number of keys removed
      def self.delete_customer_keys(dbclient, objid)
        keys = CUSTOMER_SUB_KEYS.map { |suffix| "customer:#{objid}:#{suffix}" }
        # Also try the bare key (Familia v1 pattern)
        keys << "customer:#{objid}"
        dbclient.del(*keys)
      end

      private

      # Finds the customer named by the Rodauth account's external_id.
      # @return [Onetime::Customer, nil]
      def find_by_account
        return nil unless @account && @account[:external_id]

        customer = Onetime::Customer.find_by_extid(@account[:external_id])

        if customer.nil?
          OT.info "[delete-customer] Customer not found for extid: #{@account[:external_id]}"
        end

        customer
      end

      # Deletes the customer record.
      # @param customer [Onetime::Customer]
      def delete_customer(customer)
        custid = customer.custid
        extid  = customer.extid

        customer.destroy!

        OT.info "[delete-customer] Deleted customer: #{custid} (extid: #{extid})"
      end
    end
  end
end

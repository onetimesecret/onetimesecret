# apps/web/auth/operations/change_email.rb
#
# frozen_string_literal: true

#
# Updates the auth database when a customer's email is changed via the admin CLI.
#
# ConfirmEmailChange (API flow) already handles this inline via update_auth_database.
# This operation closes the same gap for the admin CLI path (bin/ots change-email).
#
# Responsibilities:
#   1. Find account by external_id — graceful no-op if not found (simple-mode customers)
#   2. Within a transaction, update accounts.email to the new value
#   3. Delete account_active_session_keys rows (force re-auth)
#   4. Delete account_login_change_keys rows (clear stale pending changes)
#
# Usage:
#   result = Auth::Operations::ChangeEmail.call(extid: customer.extid, new_email: new_email)
#   if result[:success]
#     result[:skipped] # => true if no auth account found (simple-mode customer)
#   else
#     result[:error]   # => error message string
#   end
#

module Auth
  module Operations
    class ChangeEmail
      # @param extid [String] The customer's external ID
      # @param new_email [String] The new email address to set
      # @param db [Sequel::Database] Optional database connection (for testing)
      def initialize(extid:, new_email:, db: nil)
        @extid     = extid
        @new_email = new_email
        @db        = db || Auth::Database.connection
      end

      # Executes the email update in the auth database
      # @return [Hash] Result with :success and optionally :account_id, :skipped, :error
      def call
        return error_result('No database connection available') unless @db
        return error_result('External ID is required') if @extid.to_s.empty?
        return error_result('New email is required') if @new_email.to_s.empty?

        account = @db[:accounts].where(external_id: @extid).first

        unless account
          OT.info '[change-email-operation] No auth account found — skipping auth DB update',
            extid: @extid,
            new_email: OT::Utils.obscure_email(@new_email)
          return { success: true, skipped: true }
        end

        account_id = account[:id]

        @db.transaction do
          @db[:accounts].where(id: account_id).update(email: @new_email)

          if @db.table_exists?(:account_active_session_keys)
            @db[:account_active_session_keys].where(account_id: account_id).delete
          end

          if @db.table_exists?(:account_login_change_keys)
            @db[:account_login_change_keys].where(id: account_id).delete
          end
        end

        OT.info '[change-email-operation] Auth DB email updated',
          account_id: account_id,
          extid: @extid,
          new_email: OT::Utils.obscure_email(@new_email)

        { success: true, account_id: account_id }
      rescue Sequel::Error => ex
        OT.le "[change-email-operation] Database error: #{ex.message}"
        error_result("Database error: #{ex.message}")
      rescue StandardError => ex
        OT.le "[change-email-operation] Unexpected error: #{ex.message}"
        error_result("Unexpected error: #{ex.message}")
      end

      # Convenience class method
      def self.call(...)
        new(...).call
      end

      private

      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end

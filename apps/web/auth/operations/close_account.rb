# apps/web/auth/operations/close_account.rb
#
# frozen_string_literal: true

#
# Closes and deletes an auth account and all related data from the auth
# database (PostgreSQL/SQLite).
#
# This operation handles the complete cleanup of a user account from the
# auth database (PostgreSQL/SQLite), including all related tables with
# foreign key relationships to the accounts table.
#
# IMPORTANT: This operation should be called AFTER validating the user's
# password and BEFORE marking the Customer record as deleted in Redis.
# This ensures that if the PostgreSQL deletion fails, we don't leave
# the system in an inconsistent state.
#
# Tables cleaned up:
#   - account_password_hashes (password storage)
#   - account_password_reset_keys (pending resets)
#   - account_jwt_refresh_keys (JWT tokens)
#   - account_verification_keys (pending verifications)
#   - account_login_change_keys (pending email changes)
#   - account_remember_keys (remember me tokens)
#   - account_login_failures (brute force tracking)
#   - account_lockouts (account lockouts)
#   - account_email_auth_keys (magic link tokens)
#   - account_password_change_times (password age tracking)
#   - account_activity_times (activity tracking)
#   - account_session_keys (single session feature)
#   - account_active_session_keys (active sessions)
#   - account_webauthn_user_ids (WebAuthn user IDs)
#   - account_webauthn_keys (WebAuthn credentials)
#   - account_otp_keys (TOTP secrets)
#   - account_otp_unlocks (TOTP unlock tracking)
#   - account_recovery_codes (MFA recovery codes)
#   - account_sms_codes (SMS MFA)
#   - account_previous_password_hashes (password history)
#   - accounts (main account record)
#
# Note: account_authentication_audit_logs are deleted along with the account
# since they have a foreign key constraint. For compliance requirements,
# consider exporting audit logs before account deletion.
#
# Additionally, this operation deletes all Redis sessions associated with
# the customer's external ID to ensure complete session cleanup.
#
# Usage:
#   result = Auth::Operations::CloseAccount.new(extid: customer.extid).call
#   if result[:success]
#     # Proceed with Redis cleanup
#   else
#     # Handle error - result[:error] contains details
#   end
#

require 'onetime/operations/sessions/store'
require 'onetime/session/sidecar'

module Auth
  module Operations
    class CloseAccount
      # Tables with foreign keys referencing accounts.id
      # Order matters: delete from dependent tables first
      DEPENDENT_TABLES = [
        :account_authentication_audit_logs,
        :account_password_hashes,
        :account_password_reset_keys,
        :account_jwt_refresh_keys,
        :account_verification_keys,
        :account_login_change_keys,
        :account_remember_keys,
        :account_login_failures,
        :account_lockouts,
        :account_email_auth_keys,
        :account_password_change_times,
        :account_activity_times,
        :account_session_keys,
        :account_active_session_keys,
        :account_webauthn_keys,
        :account_webauthn_user_ids,
        :account_otp_keys,
        :account_otp_unlocks,
        :account_recovery_codes,
        :account_sms_codes,
        :account_previous_password_hashes,
      ].freeze

      # @param extid [String] The customer's external ID
      # @param db [Sequel::Database] Optional database connection (for testing)
      def initialize(extid:, db: nil)
        @extid = extid
        @db    = db || Auth::Database.connection
      end

      # Executes the account closure operation
      # @return [Hash] Result with :success, :account_id, and optionally :error
      def call
        return error_result('No database connection available') unless @db
        return error_result('External ID is required') if @extid.to_s.empty?

        account = find_account
        return error_result("No auth account found for extid: #{@extid}") unless account

        account_id = account[:id]
        email      = account[:email]

        # Delete all Redis sessions for this user first
        deleted_sessions = delete_redis_sessions(@extid)

        # Delete from auth database
        delete_account_data(account_id)

        OT.info '[close-account] Successfully deleted auth account',
          sessions_deleted: deleted_sessions,
          account_id: account_id,
          extid: @extid,
          email: OT::Utils.obscure_email(email)

        { success: true, account_id: account_id }
      rescue Sequel::Error => ex
        OT.le "[close-account] Database error during account deletion: #{ex.message}"
        OT.ld ex.backtrace.first(5).join("\n")
        error_result("Database error: #{ex.message}")
      rescue StandardError => ex
        OT.le "[close-account] Unexpected error during account deletion: #{ex.message}"
        OT.ld ex.backtrace.first(5).join("\n")
        error_result("Unexpected error: #{ex.message}")
      end

      # Convenience class method
      def self.call(...)
        new(...).call
      end

      private

      # Finds the account by external_id
      # @return [Hash, nil] The account record or nil
      def find_account
        @db[:accounts].where(external_id: @extid).first
      end

      # Deletes all account data within a transaction
      # @param account_id [Integer] The account's primary key
      def delete_account_data(account_id)
        @db.transaction do
          # Delete from all dependent tables first
          DEPENDENT_TABLES.each do |table|
            next unless @db.table_exists?(table)

            # Most tables use :id as FK, but some use :account_id
            fk_column = table_uses_account_id?(table) ? :account_id : :id

            deleted = @db[table].where(fk_column => account_id).delete
            if deleted > 0
              OT.ld "[close-account] Deleted #{deleted} row(s) from #{table}"
            end
          end

          # Finally delete the account record itself
          @db[:accounts].where(id: account_id).delete
        end
      end

      # Some tables use :account_id instead of :id as the foreign key
      # @param table [Symbol] The table name
      # @return [Boolean] true if table uses :account_id
      def table_uses_account_id?(table)
        [
          :account_jwt_refresh_keys,
          :account_active_session_keys,
          :account_webauthn_keys,
          :account_previous_password_hashes,
          :account_authentication_audit_logs,
        ].include?(table)
      end

      # Deletes all Redis sessions associated with the given external_id, and
      # purges each deleted session's per-value sidecar keys (issue #3858).
      #
      # Session values are AES-256-GCM encrypted + HMAC-signed
      # ("base64(iv+tag+ciphertext)--hmac"), so they MUST be decoded through
      # the same SessionCodec the middleware writes with. The previous
      # `JSON.parse(Base64.decode64(...))` treated the value as base64(json):
      # for authenticated sessions the base64 decodes to binary ciphertext, the
      # parse raised, and every authenticated session was silently skipped —
      # closing an account left its live sessions untouched. {Store.load_data}
      # decodes first and falls back to legacy plaintext JSON.
      #
      # @param extid [String] The customer's external ID
      # @return [Integer] Number of sessions deleted
      def delete_redis_sessions(extid)
        return 0 if extid.to_s.empty?

        dbclient      = Familia.dbclient
        deleted_count = 0
        codec         = session_codec

        # Scan for all session keys
        dbclient.scan_each(match: 'session:*') do |key|
            # Per-value sidecar keys (session:<sid>:<field>) are not session
            # blobs; they carry no external_id and are purged alongside their
            # owning blob below, so skip them up front.
            next if key.match?(Onetime::Operations::Sessions::Store::SIDECAR_KEY_PATTERN)

            session_data = Onetime::Operations::Sessions::Store.load_data(dbclient, key, codec: codec)
            next unless session_data.is_a?(Hash)

            # Check if this session belongs to the user being deleted
            session_extid = session_data['external_id'] || session_data['account_external_id']
            next unless session_extid == extid

            dbclient.del(key)
            Onetime::SessionSidecar.purge(
              Onetime::Operations::Sessions::Store.extract_id(key), dbclient: dbclient
            )
            deleted_count += 1
            OT.ld "[close-account] Deleted Redis session: #{key[0..30]}..."
        rescue StandardError => ex
            # One malformed/undecodable key must never abort the whole sweep.
            OT.ld "[close-account] Skipping session #{key}: #{ex.message}"
        end

        deleted_count
      rescue StandardError => ex
        OT.le "[close-account] Error deleting Redis sessions: #{ex.message}"
        0
      end

      # SessionCodec built from the same secret the session middleware writes
      # with — ENV['SESSION_SECRET'], then the site secret (the fallback chain
      # in Onetime::Session#initialize). Returns nil when no secret is
      # configured, in which case {Store.load_data} degrades to the legacy
      # plaintext-JSON path rather than raising.
      def session_codec
        secret = ENV.fetch('SESSION_SECRET', nil)
        secret = OT.conf.dig('site', 'secret') if secret.to_s.empty?
        return nil if secret.to_s.empty?

        Onetime::SessionCodec.new(secret)
      rescue StandardError
        nil
      end

      # Builds an error result hash
      # @param message [String] The error message
      # @return [Hash] Result with :success => false and :error
      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end

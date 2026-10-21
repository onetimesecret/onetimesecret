# apps/web/auth/operations/remove_authentication_data.rb
#
# frozen_string_literal: true

#
# Closes and deletes an auth account and all related data from the auth
# database (PostgreSQL/SQLite).
#
# Log tag `[close-account]` is kept as a stable operational identifier
# (correlates current and historical activity; renaming this class must not
# silently invalidate saved searches, dashboards, alerts, or runbooks). It
# continues to align with the public `/auth/close-account` flow rather than
# tracking the class name.
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
#   - account_identities (SSO identities)
#   - accounts (main account record; see the two modes below)
#
# Two modes (#4819):
#   - retain_account: false (administrative purge, the simple-mode delete
#     endpoint, orphan sweeps): every dependent row, the audit log included,
#     and the accounts row itself are deleted here.
#   - retain_account: true (Rodauth's after_close_account hook only): the
#     audit log and the accounts row are left in place and the row is set to
#     CLOSED, because Rodauth's audit_logging feature inserts the "Account
#     closed" row after the hook returns. Rodauth's delete_account, overridden
#     in config/hooks/account.rb, then removes the audit log and the row as
#     the last statements of the same transaction (delete_dependent_rows).
#
# Nothing of the account survives either path, the audit history included.
# Export audit logs before deletion if a compliance requirement needs them.
#
# Additionally, this operation deletes all Redis sessions associated with
# the customer's external ID to ensure complete session cleanup.
#
# Usage:
#   result = Auth::Operations::RemoveAuthenticationData.new(extid: customer.extid).call
#   if result[:success]
#     # Proceed with Redis cleanup
#   else
#     # Handle error - result[:error] contains details
#   end
#

require 'auth/account_statuses'
require 'onetime/operations/sessions/store'
require 'onetime/session/codec'
require 'onetime/session/sidecar'

module Auth
  module Operations
    class RemoveAuthenticationData
      # Tables with foreign keys referencing accounts.id
      # Order matters: delete from dependent tables first
      #
      # spec/integration/full/remove_authentication_data_dependent_tables_spec.rb
      # derives the same list from the migrated schema, so a new table with a
      # foreign key to accounts fails there until it is added here.
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
        :account_identities,
      ].freeze

      # Tables whose foreign key to accounts.id is the :account_id column.
      # Every other table in DEPENDENT_TABLES keys on its own :id.
      ACCOUNT_ID_KEYED_TABLES = [
        :account_jwt_refresh_keys,
        :account_active_session_keys,
        :account_webauthn_keys,
        :account_previous_password_hashes,
        :account_authentication_audit_logs,
        :account_identities,
      ].freeze

      # @param table [Symbol] a DEPENDENT_TABLES entry
      # @return [Symbol] the column that references accounts.id
      def self.fk_column_for(table)
        ACCOUNT_ID_KEYED_TABLES.include?(table) ? :account_id : :id
      end

      # Deletes every row that references one account, in foreign-key order.
      # Shared by #call and by Rodauth's delete_account override
      # (config/hooks/account.rb), which runs it last in the close_account
      # transaction. Runs on the caller's connection and transaction, which
      # the caller must have opened: the lock below lives exactly as long as
      # that transaction.
      #
      # The accounts row is locked first (SELECT ... FOR UPDATE; SQLite
      # ignores the clause, its writers serialize anyway). On PostgreSQL an
      # insert into a referencing table takes a KEY SHARE lock on the parent
      # row, which the status update close_account made earlier does not
      # block, so a request still in flight for the account (a login writing
      # its audit row) could otherwise commit a child row between these
      # deletes and the deletion of the row itself and fail that deletion's
      # foreign-key check, rolling the closure back after the Redis customer
      # is already gone. Held to the commit, the lock makes such an insert
      # wait and then fail on the missing parent instead.
      #
      # @param db [Sequel::Database]
      # @param account_id [Integer]
      # @param except [Array<Symbol>] DEPENDENT_TABLES entries to leave alone
      # @return [Hash{Symbol=>Integer}] rows deleted per table (non-zero only)
      def self.delete_dependent_rows(db, account_id, except: [])
        db[:accounts].where(id: account_id).for_update.get(:id)

        existing_dependent_tables(db, except: except).each_with_object({}) do |table, deleted|
          count          = db[table].where(fk_column_for(table) => account_id).delete
          deleted[table] = count if count.positive?
        end
      end

      # The DEPENDENT_TABLES present in this database, from one catalog read.
      # (Sequel's table_exists? probes one table per call, each inside a
      # savepoint when a transaction is open; 22 of those per closure was the
      # cost of checking table by table.)
      #
      # @param db [Sequel::Database]
      # @param except [Array<Symbol>] DEPENDENT_TABLES entries to leave out
      # @return [Array<Symbol>] in DEPENDENT_TABLES order
      def self.existing_dependent_tables(db, except: [])
        present = db.tables
        (DEPENDENT_TABLES - except).select { |table| present.include?(table) }
      end

      # @param extid [String] The customer's external ID
      # @param db [Sequel::Database] Optional database connection (for testing)
      # @param allow_missing [Boolean] Treat an already-absent account as success.
      #   Account deletion uses this for safe retries after a partial cross-store
      #   teardown; direct callers retain the strict default.
      # @param revoke_sessions [Boolean] Run the legacy standalone session sweep.
      #   Unified account deletion supplies false because its session operation
      #   has already completed.
      # @param retain_account [Boolean] Leave the accounts row (set to CLOSED)
      #   and its authentication audit log in place while removing credentials
      #   and related auth data. For Rodauth's after_close_account hook only:
      #   Rodauth still inserts the "Account closed" audit row after the hook,
      #   then its delete_account override removes the audit log and the row
      #   (#4819). Every other caller deletes the row and its audit log here.
      def initialize(extid:, db: nil, allow_missing: false, revoke_sessions: true,
                     retain_account: false)
        @extid           = extid
        @db              = db || Auth::Database.connection
        @allow_missing   = allow_missing
        @revoke_sessions = revoke_sessions
        @retain_account  = retain_account
      end

      # Executes the account closure operation
      # @return [Hash] Result with :success, :account_id, and optionally :error
      def call
        return error_result('No database connection available') unless @db
        return error_result('External ID is required') if @extid.to_s.empty?

        account = find_account
        return { success: true, account_id: nil } if account.nil? && @allow_missing
        return error_result("No auth account found for extid: #{@extid}") unless account

        account_id = account[:id]
        email      = account[:email]

        # Direct callers retain the standalone session sweep. TeardownAccount uses
        # the shared session operation before invoking this SQL-only phase.
        deleted_sessions = @revoke_sessions ? delete_redis_sessions(@extid) : 0

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
          # In retain mode the audit log stays for Rodauth's delete_account to
          # remove together with the row; see the class comment.
          except  = @retain_account ? [:account_authentication_audit_logs] : []
          deleted = self.class.delete_dependent_rows(@db, account_id, except: except)
          deleted.each do |table, count|
            OT.ld "[close-account] Deleted #{count} row(s) from #{table}"
          end

          if @retain_account
            @db[:accounts].where(id: account_id).update(status_id: Auth::AccountStatuses::CLOSED)
          else
            # Finally delete the account record itself
            @db[:accounts].where(id: account_id).delete
          end
        end
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
        # from_config resolves the SAME secret chain the middleware writer is
        # mounted with (session_config['secret'] → site.secret). Any other
        # chain — e.g. ENV['SESSION_SECRET'], which the middleware never
        # reads — can build a codec with the wrong key, and every encrypted
        # session silently fails to decode and survives the sweep.
        codec         = Onetime::SessionCodec.from_config

        # Scan for all session keys. STRING-typed like Store.scan_keys: the
        # loose match also catches non-string keys (the entitlement-preview
        # SETs) that would WRONGTYPE on GET. Per-value sidecar keys live under
        # `sidecar:<sid>:<field>` — outside this match by construction — and
        # are purged alongside their owning blob below.
        dbclient.scan_each(match: 'session:*', type: 'string') do |key|
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

      # Builds an error result hash
      # @param message [String] The error message
      # @return [Hash] Result with :success => false and :error
      def error_result(message)
        { success: false, error: message }
      end
    end
  end
end

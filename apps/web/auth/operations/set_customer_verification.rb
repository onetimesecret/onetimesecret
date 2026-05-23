# apps/web/auth/operations/set_customer_verification.rb
#
# frozen_string_literal: true

#
# Sets a Customer's verification state across both stores: the Familia
# Customer record in Redis and (in full auth mode) the Rodauth accounts
# row in SQL.
#
# Single home for verification state changes, regardless of caller:
#   - CLI: `bin/ots customers verify/unverify EMAIL` — drives both
#     stores.
#   - Colonel admin API (apps/api/colonel/logic/): same shape as CLI.
#   - Rodauth `after_verify_account` hook: Rodauth has already
#     committed status_id=2 in its own transaction, so the caller
#     passes `rodauth_already_synced: true` and the op skips its own
#     SQL update. Only the Redis mirror runs.
#
# `rodauth_already_synced:` is a contract parameter, not a flag:
# the caller is asserting "the Rodauth side is already correct,
# only mirror to Redis." It exists because the Rodauth hook runs
# synchronously inside Rodauth's own transaction; a redundant SQL
# write there would add a savepoint and a roundtrip with no
# semantic benefit.
#
# Cross-store consistency notes (Familia v2.9.1):
#   Familia is Redis-only — no cross-store transaction primitive
#   exists. save_with_collections is for scalar+collection co-writes
#   on a single Familia object, not Redis+SQL. We achieve consistency
#   with application-level ordering: SQL update first (inside
#   db.transaction for SQL-side atomicity), Redis save second.
#
#   Failure modes:
#     - SQL raises  → Redis untouched (clean rollback)
#     - No SQL row  → AccountNotFound, Redis untouched
#     - SQL ok, Redis raises → Rodauth fresh, Customer stale.
#       Auth state (the important one) is correct; display of
#       Customer#verified? will be wrong until next save.
#       Detectable and fixable via `bin/ots customers sync-auth-accounts`.
#

module Auth
  module Operations
    class SetCustomerVerification
      include Onetime::LoggerMethods

      class NoAuthDatabase < StandardError; end
      class AccountNotFound < StandardError; end

      # @param customer    [Onetime::Customer] target (caller ensures non-nil,
      #                    non-anonymous)
      # @param verified    [Boolean] target state
      # @param verified_by [String, nil] provenance tag ('cli_provision',
      #                    'colonel_admin', 'email', etc.); nil when clearing
      # @param rodauth_already_synced [Boolean] when true, skip the SQL
      #                    update — caller guarantees Rodauth-side
      #                    status is already correct (e.g., we're
      #                    inside after_verify_account)
      # @param db          [Sequel::Database, nil] injectable for tests and
      #                    callers with an existing connection; defaults to
      #                    Auth::Database.connection at call time
      def initialize(customer:, verified:, verified_by:, rodauth_already_synced: false, db: nil)
        @customer                = customer
        @verified                = verified
        @verified_by             = verified_by
        @rodauth_already_synced  = rodauth_already_synced
        @db                      = db
      end

      # @return [Symbol] :success or :no_change
      # @raise [NoAuthDatabase] full auth mode + DB unreachable
      #   (not raised when rodauth_already_synced: true)
      # @raise [AccountNotFound] full auth mode + no accounts row for email
      #   (not raised when rodauth_already_synced: true)
      def call
        return :no_change if @customer.verified? == @verified

        update_rodauth_account! if full_auth_mode? && !@rodauth_already_synced
        update_customer!

        auth_logger.debug "[set-customer-verification] #{@customer.extid} " \
          "verified=#{@verified} verified_by=#{@verified_by.inspect} " \
          "auth_mode=#{Onetime.auth_config.mode} " \
          "rodauth_already_synced=#{@rodauth_already_synced}"
        :success
      end

      private

      def full_auth_mode?
        Onetime.auth_config.mode == 'full'
      end

      def update_rodauth_account!
        db = @db || Auth::Database.connection
        raise NoAuthDatabase, 'Auth database unreachable' unless db

        # status_id: 1=Unverified, 2=Verified (per Rodauth convention,
        # mirrors lib/onetime/cli/customers/create_command.rb).
        # Sequel::CURRENT_TIMESTAMP lets the DB own updated_at — matches
        # sync_auth_accounts_command.rb and avoids any client-side TZ drift.
        rows = db.transaction do
          db[:accounts]
            .where(email: @customer.email)
            .update(status_id: @verified ? 2 : 1, updated_at: Sequel::CURRENT_TIMESTAMP)
        end
        return unless rows.zero?

        raise AccountNotFound, "No Rodauth account for #{@customer.email}"
      end

      def update_customer!
        @customer.verified    = @verified
        @customer.verified_by = @verified_by
        @customer.save
      end
    end
  end
end

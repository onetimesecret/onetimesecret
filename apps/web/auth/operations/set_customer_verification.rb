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
#     - Closed row  → AccountClosed, Redis untouched (see #3916)
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
      class AccountClosed < StandardError; end

      # Rodauth account statuses (mirrors change_email.rb and the
      # account_statuses reference table in migrations/001_initial.rb).
      STATUS_UNVERIFIED = 1
      STATUS_VERIFIED   = 2
      LIVE_STATUS_IDS   = [STATUS_UNVERIFIED, STATUS_VERIFIED].freeze

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
      # @raise [AccountNotFound] full auth mode + no accounts row for the
      #   customer (not raised when rodauth_already_synced: true)
      # @raise [AccountClosed] full auth mode + the customer's accounts row
      #   is Closed; verification only moves between Unverified and Verified
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

        # Sequel::CURRENT_TIMESTAMP lets the DB own updated_at — matches
        # sync_auth_accounts_command.rb and avoids any client-side TZ drift.
        # The status_id predicate makes the UPDATE a no-op on a Closed row,
        # atomically: no read-then-write window in which a concurrent close
        # could slip through.
        rows = db.transaction do
          scope = account_scope(db)
          raise AccountNotFound, "No Rodauth account for customer #{@customer.extid}" unless scope

          scope
            .where(status_id: LIVE_STATUS_IDS)
            .update(status_id: @verified ? STATUS_VERIFIED : STATUS_UNVERIFIED,
              updated_at: Sequel::CURRENT_TIMESTAMP,
            )
        end
        return if rows.positive?

        # A row exists but none of it is live: the account is Closed. Refuse —
        # verification only ever moves between Unverified and Verified;
        # resurrecting a Closed account is a different, deliberate operation.
        raise AccountClosed, "Rodauth account for customer #{@customer.extid} is closed"
      end

      # Locate this customer's accounts row, keyed on external_id — never bare
      # email. The unique index on accounts.email is PARTIAL
      # (`where status_id in (1, 2)`, migrations/001_initial.rb), so a Closed
      # row may share a live row's address: a bare-email UPDATE would either
      # resurrect the Closed account (one-row case) or trip the partial index
      # mid-statement (two-row case). See #3916.
      #
      # Rows predating the external_id backfill fall back to email, restricted
      # to unlinked rows (external_id IS NULL) — a linked row holding this
      # address belongs to a different customer.
      #
      # @return [Sequel::Dataset, nil] scope over the customer's row(s), or
      #   nil when no row exists at all
      def account_scope(db)
        extid = @customer.extid.to_s
        unless extid.empty?
          account_id = db[:accounts].where(external_id: extid).get(:id)
          return db[:accounts].where(id: account_id) if account_id
        end

        legacy = db[:accounts].where(email: @customer.email, external_id: nil)
        legacy.empty? ? nil : legacy
      end

      def update_customer!
        @customer.verified    = @verified
        @customer.verified_by = @verified_by
        @customer.save
      end
    end
  end
end

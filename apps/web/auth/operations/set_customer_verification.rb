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
#       Detectable and fixable via `bin/ots customers sync-auth-accounts`,
#       and the next call through this op (any change, including a
#       provenance-only one) reconciles the SQL row again.
#

require 'auth/account_statuses'

module Auth
  module Operations
    class SetCustomerVerification
      include Onetime::LoggerMethods

      class NoAuthDatabase < StandardError; end
      class AccountNotFound < StandardError; end
      class AccountClosed < StandardError; end

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
        @federation_claimed      = false
      end

      # Did this call apply a deferred federated subscription to the customer's
      # default workspace? Meaningful after #call. The claim is the one effect
      # a `:no_change` return can carry (see #claim_pending_federation!), so
      # callers that report or audit the call read this rather than inferring
      # "nothing happened" from the symbol.
      #
      # @return [Boolean]
      def federation_claimed?
        @federation_claimed
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
        state_changes      = @customer.verified? != @verified
        provenance_changes = @customer.verified_by.to_s != @verified_by.to_s

        unless state_changes || provenance_changes
          # Nothing to write. A repeat verification of an account that already
          # carries mailbox proof is still the operator's retry for a deferred
          # federation claim that failed after the proof was saved (see
          # #claim_pending_federation!); it is idempotent, so run it.
          claim_pending_federation! if mailbox_proven?
          return :no_change
        end

        # A provenance-only change (verified stays true, verified_by moves from
        # 'sso' to 'cli_provision', say) is how an already-Verified account
        # acquires MAILBOX proof (#4735): Rodauth's verify_account never runs
        # for a Verified row, so this is the only path. The SQL row is still
        # reconciled to the target state rather than assumed correct: an
        # earlier call can have committed SQL and then failed the Redis save
        # (failure modes above), leaving Redis reading verified while the
        # accounts row is Unverified. Only `rodauth_already_synced:` — the
        # caller's explicit guarantee — skips it. The UPDATE is idempotent on a
        # row already in the target state.
        update_rodauth_account! if full_auth_mode? && !@rodauth_already_synced
        update_customer!

        auth_logger.debug "[set-customer-verification] #{@customer.extid} " \
                          "verified=#{@verified} verified_by=#{@verified_by.inspect} " \
                          "auth_mode=#{Onetime.auth_config.mode} " \
                          "rodauth_already_synced=#{@rodauth_already_synced}"

        claim_pending_federation! if mailbox_proven?
        :success
      end

      private

      # Does this call leave the account verified with a mailbox-proof
      # provenance? Read after #update_customer! on the write path, so it
      # reflects the stamp just written.
      def mailbox_proven?
        @verified && @customer.mailbox_verified?
      end

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
            .where(status_id: AccountStatuses::LIVE)
            .update(status_id: @verified ? AccountStatuses::VERIFIED : AccountStatuses::UNVERIFIED,
              updated_at: Sequel::CURRENT_TIMESTAMP,
            )
        end
        return if rows.positive?

        # A row exists but none of it is live: the account is Closed. Refuse —
        # verification only ever moves between Unverified and Verified;
        # resurrecting a Closed account is a different, deliberate operation.
        raise AccountClosed,
          "Cannot change verification for customer #{@customer.extid}: Rodauth account is closed"
      end

      # Locate this customer's accounts row, keyed on external_id — never bare
      # email. The unique index on accounts.email is PARTIAL
      # (`where status_id in (1, 2)`, migrations/001_initial.rb), so a Closed
      # row may share a live row's address: a bare-email UPDATE would either
      # resurrect the Closed account (one-row case) or trip the partial index
      # mid-statement (two-row case). See #3916.
      #
      # Unlinked rows (external_id IS NULL) fall back to email. These are not
      # a mode-migration relic — linking is best-effort: Rodauth commits the
      # accounts row in its own transaction, then after_create_account links
      # external_id via a separate UPDATE under safe_execute
      # (hooks/account.rb), so a failure there leaves a live, unlinked row.
      # SyncSession heals such rows on next login (link-on-login,
      # sync_session.rb). The fallback is restricted to unlinked rows because
      # a LINKED row holding this address belongs to a different customer, and
      # it deliberately does NOT backfill external_id itself: link-on-login is
      # the sanctioned healer, and claiming a row by email from a verification
      # toggle is the same email-keyed guesswork #3916 removed.
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

      # Deliver the federated benefit that was deferred until mailbox proof.
      #
      # EnsureDefaultWorkspace defers the PendingFederatedSubscription claim for
      # a standard signup (until after_verify_account) and for an SSO JIT
      # account (until an operator verifies the address, #4735). Every path
      # that stamps a mailbox-proof provenance ends here — the Rodauth hook,
      # the colonel admin API, `bin/ots customers verify` — so this is the one
      # re-claim trigger. It runs on EVERY verification that leaves the account
      # mailbox-verified, not only the one that first records the proof: a
      # claim failure (Redis, billing) is swallowed below so it can never undo
      # the verification just written, which means the pending benefit would
      # otherwise be stranded with nothing left to re-drive it (the Rodauth
      # hook fires once; EnsureDefaultWorkspace#call skips an existing
      # workspace). Repeating the verification — a :no_change call included —
      # is the retry. Idempotent: a no-op when nothing is pending, when it was
      # already claimed, or when the customer owns no default workspace.
      #
      # The outcome is kept on #federation_claimed? because the return symbol
      # cannot carry it: a verification that wrote nothing but applied a
      # stranded subscription is still `:no_change` for the verification state,
      # and the grant must not be reported as "already verified" alone.
      def claim_pending_federation!
        claimed             = Onetime::ErrorHandler.safe_execute('claim_pending_federation', external_id: @customer.extid) do
          Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(@customer)
        end
        @federation_claimed = claimed == true
      end
    end
  end
end

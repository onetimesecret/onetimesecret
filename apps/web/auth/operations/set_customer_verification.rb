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
#   - Rodauth `after_verify_account` hook: Rodauth has already set
#     status_id=2 in its own transaction, and the hook writes the
#     migration 015 verification columns there too, so the caller
#     passes `rodauth_already_synced: true` and the op skips its own
#     SQL update. Only the Redis mirror runs.
#   - The self-service email change (ChangeEmail, self_service: true):
#     the redeemed link proved the new address, so it stamps 'email'
#     with `new_address: true` once the swap has landed.
#   - The emailed verification link redeemed in simple auth mode (the
#     v1 and v2 secret reveal logic): `.record_mailbox_proof`, which
#     stamps 'email' through #call, runs the federation claim only for a
#     link sent to the customer's current address, and holds that claim
#     to the customer's own address. In full auth mode it records nothing,
#     since Rodauth owns verification there (#4754 review, round 3).
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
#       and the next call through this op that writes (a state change, or
#       a provenance change that alters whether the account has mailbox
#       proof) reconciles the SQL row again. A repeat of mailbox proof
#       under another mailbox-proof tag writes nothing, like a same-stamp
#       repeat (see #mailbox_proof_reaffirmed?).
#
# Migration 015 (ADR-051): the same UPDATE that sets status_id writes the
# accounts row's verification columns (`email_verified_at`,
# `email_verified_by`, `email_verification_hold`) from the state this call
# leaves on the Customer, through Auth::AccountEmailVerification, so the two
# stores move together from the moment the columns exist and the backfill's
# copy stays current after it runs. Proof is written only for mailbox-proof
# provenances and only when the row's address is the Customer's. Under
# `rodauth_already_synced:` the caller has written them too (the
# after_verify_account hook, in Rodauth's transaction).
#

require 'auth/account_statuses'
require 'auth/account_email_verification'
# #claim_pending_federation! names EnsureDefaultWorkspace at call time, and
# not every process that loads this file has loaded that one. The auth app
# loads its operations through apps/web/auth/operations.rb, which requires
# ensure_default_workspace before this file. The v2 API, like everything
# built on Onetime::Logic::Base, reaches it through
# lib/onetime/logic/organization_context.rb, which require_relatives it at
# the top. A process that loads only the v1 API has neither, because
# V1::Logic::Base does not descend from Onetime::Logic::Base; there the
# claim would raise NameError inside safe_execute and be logged as a claim
# failure instead of claiming. So this file requires it itself. (The specs
# cannot show that gap: spec/spec_helper.rb requires onetime/logic, which
# loads the v2 logic.)
require 'auth/operations/ensure_default_workspace'

module Auth
  module Operations
    class SetCustomerVerification
      include Onetime::LoggerMethods
      extend Onetime::LoggerMethods

      class NoAuthDatabase < StandardError; end
      class AccountNotFound < StandardError; end
      class AccountClosed < StandardError; end

      # Record that a verification link delivered to the customer's address
      # was followed: the simple-auth-mode mailbox proof.
      #
      # The three secret reveal sites that redeem the emailed verification
      # secret (apps/api/v2/logic/secrets/reveal_secret.rb and
      # show_secret.rb, apps/api/v1/logic/secrets/show_secret.rb) used to
      # write `verified = true; verified_by = 'email'` straight onto the
      # Customer, so the deferred federated subscription claim that every
      # other mailbox-proof stamp triggers through #call never ran for them.
      # In a simple-mode install run without AUTHENTICATION_MODE exported, a
      # standard signup defers that claim (Customer#verification_step_pending?)
      # and the redeemed link is the only self-service proof there is, so it
      # has to be the trigger too (#4754 review, round 3). Routing the stamp
      # through #call also keeps a stored mailbox-proof stamp on a repeat
      # (#mailbox_proof_reaffirmed?) and still retries the claim.
      #
      # The claim the link runs has two limits that the stamp does not.
      #
      # It runs only for a link on record as sent to the customer's current
      # address (Secret#delivered_to?). A link is tied to the account, not to
      # an address. An operator email change (`bin/ots customers
      # change-email` or the colonel endpoint, without --keep-verified)
      # resets verification and rewrites the default workspace's contact
      # email, which the claim hashes, to the new address, but leaves the
      # links already sent to the earlier address live. Such a link proves
      # only the earlier mailbox. It still stamps, as the direct stamp did,
      # and runs no claim (claim_pending_federation: false), so it cannot
      # apply the new address's pending subscription. A link minted before
      # the delivery address was recorded runs no claim either. The pending
      # record stays for an operator verification.
      #
      # And the claim is held to the customer's own address
      # (claim_own_address_only:, EnsureDefaultWorkspace's own_address_only).
      # It hashes the workspace's billing email, else its contact email, and
      # the owner can set the billing email to any address through
      # PUT /api/organizations/:extid without proving it. The link proves
      # only the customer's own mailbox, so without the check a caller who
      # proved only their own mailbox could collect another address's pending
      # subscription, on the first stamp or on the :no_change repeat that
      # ShowSecret's anonymous branch reaches for an owner who already has
      # mailbox proof. A workspace billed to another address keeps the
      # pending record. The operator verifications (`bin/ots customers
      # verify`, the colonel admin) are held to neither limit.
      #
      # In full auth mode the link records nothing. The verification secret
      # is minted only by simple-mode flows (Core's /auth/* routes, which the
      # Auth app shadows in full mode), but the v1 and v2 secret routes that
      # redeem it load in every mode, so the full-mode case is a link minted
      # in simple mode and followed after the install switched to full mode.
      # Rodauth owns verification there: its verify_account flow runs the
      # after_verify_account hook, which stamps 'email' through #call and
      # runs the claim. Reconciling the accounts row from a secret reveal
      # instead would flip an Unverified row to Verified and let an account
      # that Rodauth blocks sign in, which this method does not do. Before
      # this method existed, the direct stamp wrote Redis alone in that case
      # and left the accounts row Unverified, so the skip narrows what the
      # link does. The reveal proceeds either way.
      #
      # Nothing is rescued. In simple mode #call touches no SQL, so its
      # full-mode errors (NoAuthDatabase, AccountNotFound, AccountClosed)
      # cannot be raised, and any error that does escape #call propagates to
      # the reveal as one from the direct stamp did. The claim itself is
      # already wrapped in #claim_pending_federation!.
      #
      # @param customer [Onetime::Customer] the verification secret's owner
      #   (caller ensures non-nil, non-anonymous, and that the secret is
      #   mailbox proof for this customer: Customer#mailbox_proof_secret?)
      # @param secret [Onetime::Secret] the verification secret being
      #   redeemed; its delivery address decides whether the claim runs
      # @return [Symbol, nil] :success or :no_change from #call; nil when the
      #   install runs full auth mode and the link recorded nothing
      def self.record_mailbox_proof(customer, secret)
        if full_auth_mode?
          auth_logger.info '[set-customer-verification] Verification link redeemed in full auth mode; ' \
                           'Rodauth owns account verification there, so the link records no mailbox proof',
            { customer: customer.extid }
          return nil
        end

        current_address = secret.delivered_to?(customer.email)
        unless current_address
          auth_logger.info '[set-customer-verification] Verification link is not on record as sent to the ' \
                           "account's current address; stamping without the federation claim",
            { customer: customer.extid, delivery_recorded: !secret.delivery_digest.to_s.empty? }
        end

        new(
          customer: customer,
          verified: true,
          verified_by: 'email',
          claim_pending_federation: current_address,
          claim_own_address_only: true,
        ).call
      end

      # The auth-mode predicate both .record_mailbox_proof and #call read, so
      # the two cannot disagree about which store owns verification.
      #
      # @return [Boolean] true when Rodauth's accounts table is in use
      def self.full_auth_mode?
        Onetime.auth_config.mode == 'full'
      end

      # @param customer    [Onetime::Customer] target (caller ensures non-nil,
      #                    non-anonymous)
      # @param verified    [Boolean] target state
      # @param verified_by [String, nil] provenance tag, one of
      #                    Onetime::Customer::VERIFIED_BY_VALUES; nil when
      #                    clearing. Not written over a stored mailbox-proof
      #                    stamp when it is mailbox proof too
      #                    (#mailbox_proof_reaffirmed?)
      # @param rodauth_already_synced [Boolean] when true, skip the SQL
      #                    update — caller guarantees the accounts row
      #                    (status and verification columns) is already
      #                    correct (e.g., we're inside after_verify_account)
      # @param db          [Sequel::Database, nil] injectable for tests and
      #                    callers with an existing connection; defaults to
      #                    Auth::Database.connection at call time
      # @param claim_pending_federation [Boolean] when false, this call runs
      #                    no federation claim, on the write path or on a
      #                    :no_change repeat, and the pending record is left
      #                    intact. Cleared by .record_mailbox_proof alone, for
      #                    a link not on record as sent to the customer's
      #                    current address
      # @param claim_own_address_only [Boolean] when true, the federation
      #                    claim this call runs applies only a pending record
      #                    for the customer's own address
      #                    (EnsureDefaultWorkspace's own_address_only). Set
      #                    by .record_mailbox_proof and the self-service email
      #                    change
      # @param new_address [Boolean] the proof is for an address the stored
      #                    stamp does not describe: the account holder just
      #                    redeemed a link sent to their new address
      #                    (ChangeEmail, self_service). The call always writes,
      #                    and a stored mailbox-proof stamp is replaced, not
      #                    kept (#mailbox_proof_reaffirmed? describes the old
      #                    address there)
      # @raise [ArgumentError] verified: true with a verified_by tag outside
      #   Onetime::Customer::VERIFIED_BY_VALUES — refused before any write,
      #   so an unknown tag can never reach either store
      def initialize(customer:, verified:, verified_by:, rodauth_already_synced: false, db: nil,
                     claim_pending_federation: true, claim_own_address_only: false, new_address: false)
        Onetime::Customer.assert_known_verified_by!(verified_by) if verified

        @customer                 = customer
        @verified                 = verified
        @verified_by              = verified_by
        @rodauth_already_synced   = rodauth_already_synced
        @db                       = db
        @claim_pending_federation = claim_pending_federation
        @claim_own_address_only   = claim_own_address_only
        @new_address              = new_address
        @federation_claimed       = false
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
        provenance_changes = @customer.verified_by.to_s != @verified_by.to_s && !mailbox_proof_reaffirmed?

        unless state_changes || provenance_changes || @new_address
          # Nothing to write. A repeat verification of an account that already
          # carries mailbox proof is still the operator's retry for a deferred
          # federation claim that failed after the proof was saved (see
          # #claim_pending_federation!); it is idempotent, so run it.
          if @customer.verified_by.to_s != @verified_by.to_s
            auth_logger.debug "[set-customer-verification] #{@customer.extid} keeps " \
                              "verified_by=#{@customer.verified_by.inspect}; " \
                              "#{@verified_by.inspect} records no new fact"
          end
          claim_pending_federation! if mailbox_proven?
          return :no_change
        end

        # A provenance-only change that ALTERS whether the account has mailbox
        # proof (verified stays true, verified_by moves from 'sso' to
        # 'cli_provision', say) is how an already-Verified account acquires
        # MAILBOX proof (#4735): Rodauth's verify_account never runs for a
        # Verified row, so this is the only path. The SQL row is still
        # reconciled to the target state rather than assumed correct: an
        # earlier call can have committed SQL and then failed the Redis save
        # (failure modes above), leaving Redis reading verified while the
        # accounts row is Unverified. Only `rodauth_already_synced:` — the
        # caller's explicit guarantee — skips it. The UPDATE is idempotent on a
        # row already in the target state. A provenance move between two
        # mailbox-proof tags never gets here (#mailbox_proof_reaffirmed?), so
        # it reconciles nothing, exactly like a same-stamp repeat.
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

      # Does this call re-stamp mailbox proof onto an account that already has
      # it? `bin/ots customers verify` ('cli_provision') and the colonel admin
      # ('colonel_admin') are the documented retry for a stranded federation
      # claim, and either one run on an account the Rodauth hook stamped
      # 'email' used to rewrite that provenance to the operator's tag (#4754
      # review, F2). Both tags say the same thing, that the mailbox was
      # proven, and the stored one says how it was proven, which nothing
      # records anywhere else and Rodauth never stamps again (verify_account
      # never runs for a Verified row). So the move is treated as no change:
      # the stored stamp is kept and the claim retry still runs.
      #
      # Reads Customer#mailbox_verified? for the stored side, which includes
      # verified?, so a stale mailbox tag on an UNVERIFIED record (the
      # pre-#4735 `customers create --no-verified` stamped 'cli_provision'
      # regardless) is not mistaken for proof; that call is a state change
      # and writes as before. A move from a mailbox-proof tag to a
      # non-mailbox one with verified: true is not refused here (no caller
      # does it; the doctor passes an existing stamp only for an unverified
      # record) and would still write.
      #
      # Not under `new_address:`: the stored stamp proved the old address.
      #
      # @return [Boolean]
      def mailbox_proof_reaffirmed?
        return false if @new_address

        @verified && @customer.mailbox_verified? &&
          Onetime::Customer::MAILBOX_VERIFIED_BY.include?(@verified_by.to_s)
      end

      def full_auth_mode?
        self.class.full_auth_mode?
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

          live = scope.where(status_id: AccountStatuses::LIVE)
          live.update(status_id: @verified ? AccountStatuses::VERIFIED : AccountStatuses::UNVERIFIED,
            updated_at: Sequel::CURRENT_TIMESTAMP,
            **email_verification_values(db, live),
          )
        end
        return if rows.positive?

        # A row exists but none of it is live: the account is Closed. Refuse —
        # verification only ever moves between Unverified and Verified;
        # resurrecting a Closed account is a different, deliberate operation.
        raise AccountClosed,
          "Cannot change verification for customer #{@customer.extid}: Rodauth account is closed"
      end

      # The migration 015 columns for the state this call leaves, read for
      # the live row's own address: proof the Customer has for another
      # mailbox (the stores disagree on the address, which
      # `customers doctor` reports as auth_email_drift) clears them. Empty on
      # a database without the columns.
      #
      # @return [Hash]
      def email_verification_values(db, live)
        return {} unless AccountEmailVerification.columns?(db)

        AccountEmailVerification.values_for_row(
          live.get(:email),
          @customer.email,
          verified: @verified,
          verified_by: @verified_by,
          hold: @customer.verification_hold,
        )
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
      # a standard signup (until after_verify_account, or until the emailed
      # link is redeemed in simple auth mode) and for an SSO JIT account (until
      # an operator verifies the address, #4735). Every path that stamps a
      # mailbox-proof provenance ends here (the Rodauth hook, the colonel
      # admin API, `bin/ots customers verify`, the redeemed verification link
      # in simple auth mode through .record_mailbox_proof, which runs the
      # claim only for a link sent to the customer's current address and
      # holds it to that address), so this is the one
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
        # Declined by the caller: .record_mailbox_proof, for a link not on
        # record as sent to the customer's current address. The pending
        # record is left intact.
        return unless @claim_pending_federation

        claimed             = Onetime::ErrorHandler.safe_execute('claim_pending_federation', external_id: @customer.extid) do
          Auth::Operations::EnsureDefaultWorkspace.claim_pending_federation_for(
            @customer, own_address_only: @claim_own_address_only
          )
        end
        @federation_claimed = claimed == true
      end
    end
  end
end

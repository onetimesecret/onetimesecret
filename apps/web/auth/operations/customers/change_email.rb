# apps/web/auth/operations/customers/change_email.rb
#
# frozen_string_literal: true

# Loaded from the auth app AND from the CLI (which runs outside the auth app's
# autoloader), so every dependency is required explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/jobs/publisher'
require 'onetime/operations/sessions/revoke_all_for_customer'
require 'auth/account_statuses'
require 'auth/operations/customers/set_verification'

module Auth
  module Operations
    module Customers
      # Change a customer's account email address across EVERY store keyed on it.
      #
      # The ONE implementation of the change-email mutation (#3731 PR-C1). The
      # self-service `AccountAPI::Logic::Account::ConfirmEmailChange` token path,
      # the colonel endpoint and `bin/ots customers change-email` are all intended
      # to be thin adapters over it. Adapters own resolution, token validation,
      # prompts and output; they NEVER re-implement the mutation and never emit
      # the audit event.
      #
      # ## THIS IS A CROSS-STORE MUTATION WITH NO DISTRIBUTED TRANSACTION
      #
      # In `AUTHENTICATION_MODE=full` the address lives in Postgres (the Rodauth
      # `accounts` row) AND in Redis (the Familia Customer hash plus three
      # indexes). Familia is Redis-only; there is no primitive that spans both.
      # The ratified doctrine (see set_customer_verification.rb:26-39) is
      # application-level ordering plus detection, and it has three parts here —
      # all three are load-bearing:
      #
      #   1. SQL FIRST, inside `db.transaction`. A SQL failure leaves Redis
      #      completely untouched (clean rollback, nothing to compensate).
      #   2. COMPENSATION + `:partial`. If the Redis write fails after the SQL
      #      commit, the old address is written back to `accounts` (best effort)
      #      and the call returns `:partial`. `:partial` is a terminal status, not
      #      an exception: raising past a mutation that already committed to SQL
      #      would lose the audit record of a change that half-happened (D38).
      #      The write-back is SKIPPED once the Customer hash has committed the
      #      new address — at that point both authoritative stores agree and
      #      rolling SQL back would MANUFACTURE the drift it is meant to prevent.
      #      Only the secondary indexes are behind, which is what (3) finds.
      #   3. DETECTION. `Auth::Operations::Customers::Doctor` grew three checks
      #      for exactly this: `:auth_email_drift` (Redis vs SQL — before it, the
      #      doctor only ever compared Redis against Redis, so a `:partial` run
      #      was UNDETECTABLE), `:org_email_index_stale` and
      #      `:org_contact_email_stale`.
      #
      # ## Collision checking is genuinely two-sided, and neither side is enough
      #
      # `Onetime::Customer.email_exists?` reads `customer:email_index` and does
      # NOT normalize (customer.rb:353) — so we normalize once, up front, and use
      # the normalized value everywhere. On the SQL side `accounts.email` is
      # `citext` (case-insensitive) with a PARTIAL unique index
      # `where status_id in (1, 2)` (migrations/001_initial.rb:26,32). A CLOSED
      # account (status_id 3) therefore holds an address that is invisible to
      # BOTH the Redis index and the unique constraint. Reusing such an address
      # is still ambiguous for any email-keyed lookup (#3916 re-keyed
      # `SetCustomerVerification#update_rodauth_account!` on external_id for
      # exactly this reason), so a closed-account holder is treated as
      # `:email_taken` unless the caller explicitly passes
      # `allow_closed_account_reuse: true`.
      #
      # ## Uniqueness under concurrency: guarded in full mode, one-sided in simple
      #
      # FULL MODE is guarded, and the guard is the accounts row, not this code.
      # `accounts.email` carries a unique index (partial on `status_id in (1,2)`
      # under PostgreSQL — migrations/001_initial.rb:31-35) and every writer goes
      # through it BEFORE it touches Redis: this op updates SQL first (step 1) and
      # signup INSERTs the accounts row before `after_create_account` creates the
      # Customer (config/hooks/account.rb:176-200). So the database serializes the
      # claim, the loser never reaches its Redis write at all, and our own loss
      # surfaces as `Sequel::UniqueConstraintViolation`, which is rescued and
      # mapped to `:email_taken`.
      #
      # That guard depends on there BEING an accounts row. A customer without one
      # (a provisioning gap `bin/ots customers sync-auth-accounts` owns) updates
      # nothing in step 1, so no constraint ever fires — which is why the claim
      # below keys on the accounts row, not on the connection.
      #
      # SIMPLE MODE has no SQL and therefore no such serialization point. We claim
      # the index entry with `HSETNX` (`index_claim_race_lost?`), which IS atomic:
      # a concurrent claimant can no longer slip between our check and our write
      # and have its entry silently stolen by us. What HSETNX cannot do is stop
      # the reverse — Familia auto-adds class `unique_index` entries on EVERY save
      # with a blind `HSET` (indexing.rb:64-67, unique_index_generators.rb:430-438;
      # `update_in_class_email_index` is likewise a blind MULTI of HDEL+HSET), so a
      # writer that lands after our claim still overwrites it. Closing that
      # direction means making every writer claim-once (a Lua CAS inside Familia,
      # since the HSETNX-on-declared-field trap rules out the naive fix for object
      # fields). That is a Familia-level change and is deliberately not attempted
      # here.
      #
      # ## Audit: one event per VERB, not one per call
      #
      # This op records exactly one `customer.change_email` event. The nested
      # `Sessions::RevokeAllForCustomer` and `Customers::SetVerification` calls
      # each record their OWN distinct verb (`session.revoke_all`,
      # `customer.set_verification`). That is one-event-per-verb under epic #20
      # CONTRACT 4 and is NOT double-recording — do not "fix" it by suppressing
      # them; the sub-events are what make the trail replayable.
      #
      # ## `require_verification` has a real cost — that is why it is a parameter
      #
      # Resetting verification is correct for an operator-initiated change (nobody
      # has proven ownership of the new address), and wrong for the token path
      # (the token IS the proof). It is not free: `CreateDefaultWorkspace`
      # (create_default_workspace.rb:33-51) gates a pending cross-region federated
      # subscription claim on verification, so a reset can strip a paying
      # customer's federated benefit until they re-verify (D34).
      #
      # When it IS requested it is not best-effort. The swap has already committed
      # by the time the reset runs, so a raise here would destroy the audit of a
      # change that DID happen (D38) — but "does not raise" must not degrade into
      # "goes unnoticed". An account left flagged VERIFIED on an address nobody
      # has proven ownership of is precisely the state verification exists to
      # prevent. So every failure path is force-cleared row-scoped
      # (`force_clear_verification!`), and if even that cannot confirm the flag is
      # down the call returns `:verification_not_reset` — NOT `:success`.
      #
      # The reset is owed on the landed-`:partial` sub-case too, on the same
      # gate: the swap committed there as well, so "flagged verified on an
      # unproven address" is the same unsafe state. That path cannot downgrade a
      # status that is already `:partial`, so it carries the identical signal as
      # the `:verification_not_reset` WARNING instead.
      #
      # ## Deliberately NOT touched
      #
      # * `Organization#billing_email` / `#stripe_checkout_email` / `#email_hash`
      #   — deliberately decoupled from the account email
      #   (billing/operations/webhook_handlers/customer_updated.rb:26-28); they
      #   have their own verb, `bin/ots billing sync-billing-email`.
      # * `OrganizationMembership#invited_email` on pending invites — rewriting it
      #   would let an operator redirect a THIRD PARTY's invitation into this
      #   account. Orphaned invites are surfaced as a warning only.
      # * `EmailSuppression` entries — suppression follows the address, not the
      #   account. Auto-clearing one from an admin verb is a deliverability
      #   foot-gun; a suppressed NEW address is surfaced as a warning.
      # * A shared organization's `contact_email`. Only `is_default` personal
      #   workspaces whose contact still equals the OLD address are rewritten (D39).
      # rubocop:disable Metrics/ClassLength
      class ChangeEmail
        include Onetime::LoggerMethods
        include Onetime::AuditedFailure

        AUDIT_VERB = 'customer.change_email'

        # A privileged mutation was asked for and REFUSED before anything moved.
        # Each records one `result: :failure` event. `:no_change` and `:planned`
        # are NOT refusals — nothing was attempted that could fail. `:partial`
        # and `:verification_not_reset` are not here either: the swap LANDED and
        # `record_audit` already writes them as their own result strings (D38).
        REFUSAL_STATUSES = [:not_found, :invalid_email, :email_taken].freeze

        # This is the highest-value account-takeover primitive an operator has.
        # A non-unique-violation SQL failure re-raises from the middle of the
        # swap (call:267), BEFORE record_audit, so an attempted takeover that
        # blew up left NOTHING in the trail. Records one `result: :failure` and
        # re-raises.
        #
        # The verb is deliberately AUDIT_VERB and never the side-effect verb this
        # op also emits (`customer.set_verification`, from the composed
        # SetVerification call) — the failure belongs to the change_email verb.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only. Addresses are OBSCURED, as in record_audit.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { failure_target },
          detail: -> { { dry_run: @dry_run, to: OT::Utils.obscure_email(@new_email.to_s) } }

        # Compare-and-delete on the global email index: drop the field ONLY while
        # it still names us (`release_index_claim`). A read-then-HDEL is NOT good
        # enough and the difference is a real unindexing bug: `@index_claim_created`
        # proves we won the HSETNX, not that we still hold the field. Familia's
        # auto-index on save is a blind HSET (indexing.rb:64-67), so a customer who
        # completed signup on this address in between already owns the entry — and
        # a bare HDEL would unindex a LIVE account, leaving it findable by neither
        # `Customer.find_by_email` nor its owner. Same Lua-CAS shape ADR-019 uses
        # for the one-way claim on `secret_value_shown_at` (access_timeline.rb).
        #
        # Comparing RAW stored bytes is sound only because a `unique_index`
        # hashkey is declared `reference: true` (familia
        # unique_index_generators.rb:88-95), so a String identifier is stored
        # verbatim rather than JSON-encoded — the objid we pass IS what HSETNX
        # wrote. A non-reference collection would need the encoded form.
        # @return [Integer] 1 when the entry was ours and is now gone, else 0
        RELEASE_INDEX_CLAIM_SCRIPT = <<~LUA
          if redis.call('HGET', KEYS[1], ARGV[1]) ~= ARGV[2] then return 0 end
          return redis.call('HDEL', KEYS[1], ARGV[1])
        LUA

        # @!attribute status [r]
        #   @return [Symbol] one of:
        #     :planned       — dry run; nothing mutated, recorded as one
        #                      observation (#4337)
        #     :success       — both authoritative stores hold the new address
        #     :no_change     — normalized new address equals the current one;
        #                      recorded (#4337): on the operator trail with
        #                      outcome: 'no_change' when live, as a preview
        #                      observation on a dry run
        #     :not_found     — no usable customer (nil / anonymous / no email)
        #     :invalid_email — new address failed format validation
        #     :email_taken   — another account holds the address (Redis, SQL, or
        #                      the unique constraint itself)
        #     :partial       — SQL committed but the Redis side did not complete;
        #                      see `warnings` for which way the drift runs
        #     :verification_not_reset
        #                    — the swap LANDED but `require_verification: true`
        #                      could not be honoured: the account is still marked
        #                      verified on an address nobody has proven ownership
        #                      of. Terminal and NOT success; the operator must run
        #                      `bin/ots customers unverify <extid>`.
        # @!attribute warnings [r]
        #   @return [Array<Symbol>] surfaced-but-not-acted-on conditions
        Result = Data.define(
          :status,
          :extid,
          :from,
          :to,
          :dry_run,
          :auth_row_updated,
          :orgs_reindexed,
          :sessions_revoked,
          :verification_reset,
          :warnings,
        )

        # @param customer [Onetime::Customer, nil] target. Caller resolves; a nil
        #   or anonymous customer yields :not_found rather than raising.
        # @param new_email [String] raw address; normalized ONCE here.
        # @param actor [String, #extid, #email] acting principal's PUBLIC identity
        #   — the `Customers::Shared::CLI_ACTOR` sentinel from the CLI, the
        #   colonel's extid from the console. Never an internal objid, never a
        #   synthesized Customer (ADR-023).
        # @param dry_run [Boolean] preview only (default TRUE — this verb is
        #   destructive; `Operations::Domains::Remove` doctrine).
        # @param require_verification [Boolean] reset verification after the swap.
        #   TRUE for operator-initiated changes, FALSE for the token path. See the
        #   federated-claim cost above (D34).
        # @param revoke_sessions [Boolean] kill every session for the account.
        # @param notify [Boolean] mail BOTH the old and the new address (D36).
        #   `false` covers compromised-account remediation where the OLD address
        #   is attacker-controlled.
        # @param reason [String, nil] free-text operator reason, recorded in the
        #   audit detail (D41).
        # @param ticket [String, nil] support ticket reference, recorded in the
        #   audit detail (D41).
        # @param allow_closed_account_reuse [Boolean] permit an address held by a
        #   CLOSED Rodauth account (invisible to both normal collision checks).
        # @param db [Sequel::Database, nil] injectable; defaults to
        #   `Auth::Database.connection` at call time (nil in simple mode).
        def initialize(customer:, new_email:, actor:, dry_run: true,
                       require_verification: true, revoke_sessions: true, notify: true,
                       reason: nil, ticket: nil, allow_closed_account_reuse: false, db: nil)
          @customer                   = customer
          @new_email                  = OT::Utils.normalize_email(new_email)
          @actor                      = actor
          @dry_run                    = dry_run
          @require_verification       = require_verification
          @revoke_sessions            = revoke_sessions
          @notify                     = notify
          @reason                     = reason
          @ticket                     = ticket
          @allow_closed_account_reuse = allow_closed_account_reuse
          @db                         = db
          @warnings                   = []
        end

        # @return [Result]
        def call
          return failure(:not_found) unless usable_customer?

          old_email = @customer.email.to_s
          return failure(:invalid_email) unless Onetime::Utils::EmailFormat.valid_format?(@new_email)

          if OT::Utils.normalize_email(old_email) == @new_email
            record_no_change_event(old_email)
            return terminal(:no_change, old_email)
          end

          taken = collision_status
          return terminal(taken, old_email) if taken

          # Read-only observations, computed BEFORE any mutation (they read the
          # OLD address) so a dry run and an apply surface the same list.
          preflight_warnings

          # DRY RUN: preview only. Mutates nothing, so nothing reaches the
          # OPERATOR trail — but it resolves and reports a customer's current
          # address and the orgs a change would reindex, so it is recorded as
          # an OBSERVATION (#4337).
          if @dry_run
            record_preview_event(old_email, organizations.size)
            return terminal(:planned, old_email, orgs: organizations.size)
          end

          # --- 1. SQL FIRST (transactional). On failure Redis is untouched. ---
          begin
            auth_row_updated = update_auth_row!
          rescue StandardError => ex
            return terminal(:email_taken, old_email) if unique_violation?(ex)

            raise
          end

          # With no SQL serialization point the index entry is CLAIMED
          # (atomically) as late as possible — the last statement before the
          # first Redis write. No-op once an accounts row carries the claim for
          # us (see class docs).
          return terminal(:email_taken, old_email) if index_claim_race_lost?

          # --- 2. REDIS (compensable). ---
          customer_committed = false
          begin
            customer_committed = rekey_customer!(old_email)
            @orgs_reindexed    = reindex_orgs(old_email)
            rewrite_default_org_contacts(old_email)
            clear_pending_change
          rescue StandardError => ex
            return partial(old_email, auth_row_updated, customer_committed, ex)
          end

          # --- 3. FOLLOW-UP. Never invalidates the swap, but see below: the
          # verification reset is allowed to downgrade the STATUS. ---
          sessions_revoked   = revoke_sessions
          verification_state = reset_verification
          send_notifications(old_email)

          # The swap landed either way — that is why this is a status and not a
          # raise. But an account still flagged verified on an unproven address
          # must not be reported as a clean success.
          status = verification_state == :still_verified ? :verification_not_reset : :success

          record_audit(status, old_email, auth_row_updated)

          OT.info "[customer.change_email] #{@customer.extid} status=#{status} " \
                  "#{OT::Utils.obscure_email(old_email)} -> #{OT::Utils.obscure_email(@new_email)} " \
                  "auth_row=#{auth_row_updated} orgs=#{@orgs_reindexed} warnings=#{@warnings.inspect}"

          Result.new(
            status: status,
            extid: @customer.extid,
            from: old_email,
            to: @new_email,
            dry_run: false,
            auth_row_updated: auth_row_updated,
            orgs_reindexed: @orgs_reindexed,
            sessions_revoked: sessions_revoked,
            verification_reset: verification_state == :reset,
            warnings: @warnings.uniq,
          )
        end

        private

        # ---------------------------------------------------------------- guards

        def usable_customer?
          return false if @customer.nil?
          return false if @customer.respond_to?(:anonymous?) && @customer.anonymous?

          !@customer.email.to_s.strip.empty?
        end

        # Both stores are consulted and they genuinely disagree (see class docs).
        # @return [Symbol, nil] :email_taken, or nil when the address is free
        def collision_status
          return :email_taken if redis_holder_conflict?

          sql_collision_status
        end

        # `Customer.email_exists?` does not normalize, so we pass the normalized
        # value. An entry pointing at OURSELVES is pre-existing index drift, not a
        # collision — proceed and let the re-key repair it.
        def redis_holder_conflict?
          holder = Onetime::Customer.email_index.get(@new_email)
          !holder.nil? && holder.to_s != @customer.objid.to_s
        end

        # @return [Symbol, nil]
        def sql_collision_status
          db = connection
          return nil unless db

          rows = db[:accounts].where(email: @new_email).select(:id, :status_id).all
          return nil if rows.empty?

          mine   = auth_account_id(db)
          others = mine.nil? ? rows : rows.reject { |row| row[:id] == mine }
          return nil if others.empty?

          # A live holder is a hard collision (the partial unique index would
          # reject the UPDATE anyway).
          return :email_taken if others.any? { |row| AccountStatuses::LIVE.include?(row[:status_id]) }

          # Only CLOSED holders remain: invisible to the unique index AND to
          # Customer.email_exists?, so the write WOULD succeed and leave two
          # rows sharing an address — the contested state that made email-keyed
          # verification writes unsafe (#3916).
          return :email_taken unless @allow_closed_account_reuse

          @warnings << :new_address_held_by_closed_account
          nil
        rescue StandardError => ex
          # A probe failure must not silently downgrade to "address is free" —
          # the UPDATE's unique constraint is still the authoritative guard, but
          # the operator should see that the pre-check did not run.
          auth_logger.error '[customer.change_email] SQL collision probe failed', exception: ex
          @warnings << :sql_collision_probe_failed
          nil
        end

        # ------------------------------------------------------------------ SQL

        def connection
          @connection ||= @db || (defined?(Auth::Database) ? Auth::Database.connection : nil)
        end

        def auth_account_id(db)
          return @auth_account_id if defined?(@auth_account_id)

          extid            = @customer.extid.to_s
          row              = extid.empty? ? nil : db[:accounts].where(external_id: extid).first
          @auth_account_id = row && row[:id]
        end

        # SQL FIRST, inside db.transaction. Returns whether a row was updated;
        # `false` is the honest answer in simple mode / when no accounts row
        # exists, never a phantom success.
        # @return [Boolean]
        def update_auth_row!
          db = connection
          return false unless db

          account_id = auth_account_id(db)
          return false unless account_id

          rows = db.transaction do
            db[:accounts]
              .where(id: account_id)
              .update(email: @new_email, updated_at: Sequel::CURRENT_TIMESTAMP)
          end
          rows.to_i.positive?
        end

        # Best-effort restore of the previous address. Used ONLY when the Customer
        # hash never committed the new value (see class docs).
        # @return [Boolean] whether the write-back succeeded
        def compensate_auth_row!(old_email)
          db = connection
          return false unless db

          account_id = auth_account_id(db)
          return false unless account_id

          db.transaction do
            db[:accounts]
              .where(id: account_id)
              .update(email: old_email, updated_at: Sequel::CURRENT_TIMESTAMP)
          end
          true
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] compensating write-back FAILED', exception: ex
          false
        end

        def unique_violation?(ex)
          defined?(Sequel::UniqueConstraintViolation) && ex.is_a?(Sequel::UniqueConstraintViolation)
        end

        # ---------------------------------------------------------------- Redis

        # Field first, THEN the class index re-key, THEN save. The order matters:
        # `update_in_class_email_index` reads the CURRENT field for the new value
        # and removes the key named by its argument. `save` alone would leave the
        # stale old key behind — Familia auto-ADDS on save but never auto-removes
        # (familia indexing.rb:65-67).
        # @return [Boolean] true once the hash has committed the new address
        def rekey_customer!(old_email)
          @customer.email = @new_email
          @customer.update_in_class_email_index(old_email)
          @customer.save
          true
        end

        # ATOMICALLY claim the global email index entry whenever no SQL
        # constraint will serialize the claim for us. Skipped only when this
        # customer HAS an accounts row — there the unique index on accounts.email
        # is the real guard, it is consulted before any Redis write, and its
        # violation is rescued on the UPDATE.
        #
        # Keyed on the accounts row rather than on the connection: a full-mode
        # customer with NO row (a provisioning gap `sync-auth-accounts` owns)
        # updates nothing in `update_auth_row!`, so no constraint ever fires and
        # this claim is the only guard left.
        #
        # `HSETNX` sets the field only if it does not already exist, so the check
        # and the claim are one operation and a concurrent claimant can no longer
        # be overwritten by us. (Safe here precisely because these fields are
        # index entries keyed BY ADDRESS, not declared Familia fields — declared
        # fields are persisted as the literal string "null", which is why HSETNX
        # never fires on them.)
        #
        # A pre-existing entry pointing at OURSELVES is index drift, not a
        # collision: proceed and let the re-key repair it.
        #
        # RESIDUAL (deliberate, documented in the class docs): this closes the
        # direction where WE steal someone else's claim. It cannot close the
        # reverse — Familia's auto-index on save is a blind HSET, so a writer that
        # lands after our claim still overwrites it. That needs a claim-once
        # primitive inside Familia itself.
        #
        # NOT rescued: with no accounts row nothing has committed at this point,
        # so a datastore error here is a clean abort with nothing to compensate.
        # @return [Boolean] true when another account holds the address
        def index_claim_race_lost?
          db = connection
          return false if db && auth_account_id(db)

          index = Onetime::Customer.email_index
          if index_claimed?(index.hsetnx(@new_email, @customer.objid))
            # Remember that WE created this entry. Unlike the old pure-read
            # check, winning the claim is a mutation, so if the Redis phase then
            # fails the entry would point at a customer that never took the
            # address. `partial` releases it (best effort, `release_index_claim`)
            # and only warns when even that cannot be done.
            @index_claim_created = true
            return false
          end

          index.get(@new_email).to_s != @customer.objid.to_s
        end

        # The client boolifies HSETNX (`true`/`false`), the raw protocol answers
        # 1/0, and Familia's own signature documents the Integer. Accept both
        # rather than depending on which layer answers.
        def index_claimed?(reply)
          reply == true || reply.to_s == '1'
        end

        # The org-scoped index (`organization:<objid>:email_index`) is NOT
        # auto-populated on save, so every org the customer belongs to must be
        # re-keyed individually.
        # @return [Integer] orgs successfully re-indexed
        def reindex_orgs(old_email)
          count = 0
          organizations.each do |org|
            @customer.update_in_organization_email_index(org, old_email)
            count += 1
          rescue StandardError => ex
            auth_logger.error '[customer.change_email] org email index re-key failed',
              extid: @customer.extid,
              exception: ex
            @warnings << :org_email_index_failed
          end
          count
        end

        # D39: ONLY `is_default` personal workspaces whose contact still equals
        # the OLD address. A shared org's billing contact is never rewritten from
        # one member's personal email change.
        def rewrite_default_org_contacts(old_email)
          normalized_old = OT::Utils.normalize_email(old_email)

          organizations.each do |org|
            next unless default_org?(org)
            next unless OT::Utils.normalize_email(org.contact_email.to_s) == normalized_old

            holder = Onetime::Organization.contact_email_index.get(@new_email)
            if !holder.nil? && holder.to_s != org.identifier.to_s
              @warnings << :org_contact_email_conflict
              next
            end

            org.contact_email = @new_email
            org.update_in_class_contact_email_index(old_email)
            org.save
            @warnings << :org_contact_email_updated
          rescue StandardError => ex
            auth_logger.error '[customer.change_email] org contact_email rewrite failed',
              extid: @customer.extid,
              exception: ex
            @warnings << :org_contact_email_failed
          end
        end

        # A live self-service pending change points at a DIFFERENT new address; if
        # its token were redeemed later it would flip the account a SECOND time and
        # silently revert this change.
        #
        # DELIBERATELY NOT RESCUED: failing to clear the marker leaves that live
        # token redeemable, which is a "the change did not fully land" condition,
        # not a warning — it propagates to the compensable block and yields
        # `:partial`.
        def clear_pending_change
          token = @customer.pending_email_change.to_s

          @customer.pending_email_change.delete!
          @customer.pending_email_delivery_status.delete!

          return if token.empty?

          @warnings << :pending_self_service_change_cleared

          # Tidy-up only, so this one IS rescued: the marker deletion above
          # already makes the token unredeemable (ConfirmEmailChange#raise_concerns
          # secure_compares it against the marker), leaving at worst an orphan
          # secret that expires on its own 24h TTL.
          begin
            Onetime::Secret.find_by_identifier(token)&.destroy!
          rescue StandardError => ex
            auth_logger.error '[customer.change_email] pending secret destroy failed',
              extid: @customer.extid,
              exception: ex
            @warnings << :pending_secret_destroy_failed
          end
        end

        def organizations
          @organizations ||= begin
            @customer.organization_instances.to_a
          rescue StandardError => ex
            auth_logger.error '[customer.change_email] organization enumeration failed',
              extid: @customer.extid,
              exception: ex
            @warnings << :org_enumeration_failed
            []
          end
        end

        # `is_default` is a conservative boolean: absent/blank means NOT default.
        def default_org?(org)
          org.respond_to?(:is_default) && org.is_default.to_s == 'true'
        end

        # ------------------------------------------------------- follow-up work

        # Delegated, never re-implemented. The homegrown SCAN-and-decrypt block in
        # ConfirmEmailChange is strictly inferior: at ~200k accounts a scan-first
        # design can exhaust its cap before reaching the target's blobs and still
        # report success (revoke_all_for_customer.rb:34-43).
        # @return [Boolean]
        def revoke_sessions
          return false unless @revoke_sessions

          # `customer:` not `custid: @customer.extid` — we hold the record, so
          # the op must act on it rather than on whatever the extid index
          # resolves to (index drift, #4205/#4217, would otherwise degrade this
          # to a silent zero-count revoke).
          Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            customer: @customer,
            actor: @actor,
          ).call
          true
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] session revoke failed',
            extid: @customer.extid,
            exception: ex
          @warnings << :sessions_revoke_failed
          false
        end

        # Delegated to the admin verification wrapper so the SQL status_id and the
        # Redis mirror move together (and so the reset is itself audited).
        #
        # Does not raise — the swap has already committed and a raise would lose
        # its audit (D38) — but every way of NOT resetting is caught and either
        # force-cleared or escalated to `:verification_not_reset`. No path here
        # leaves the account verified and still reports plain success.
        #
        # @return [Symbol] :skipped (not requested) | :reset | :still_verified
        def reset_verification
          return :skipped unless @require_verification

          # Since #3916 the wrapper's SQL write keys on external_id and only
          # updates live rows (set_customer_verification.rb,
          # update_rodauth_account!), so it can no longer move a sibling row
          # sharing this address — the old resurrection hazard is gone. The
          # guard remains as a shortcut: one warning confirmed a closed holder,
          # the other left the SQL state unverified, and either way the wrapper
          # may raise (AccountNotFound, AccountClosed) where this reset must
          # still succeed. The rescue below would force-clear after such a
          # raise anyway; going straight to the row-scoped clear — conditional,
          # only ever able to REMOVE access from this customer's own row —
          # skips the failed attempt.
          return force_clear_verification! if sibling_row_possible?

          begin
            result = Auth::Operations::Customers::SetVerification.new(
              customer: @customer,
              verified: false,
              actor: @actor,
              verified_by: nil,
              # A credential-provenance reset, not an administrative unverify:
              # the address changed and is now unproven. #4328's last-colonel
              # interlock must not refuse it — leaving a colonel "verified"
              # against an address nobody controls is worse than the lockout.
              enforce_interlocks: false,
              db: @db,
            ).call
            return :reset if result == :success

            # :no_change. The wrapper decides on the REDIS mirror alone and
            # returns before touching SQL (set_customer_verification.rb:76), so
            # this only means "already unverified" when the two stores agree.
            # When they do not, the authoritative login gate (accounts.status_id)
            # is STILL Verified and nothing was reset — the quietest version of
            # exactly the state this reset exists to prevent.
            return :reset unless auth_row_verified?

            @warnings << :verification_mirror_drift
          rescue StandardError => ex
            auth_logger.error '[customer.change_email] verification reset failed',
              extid: @customer.extid,
              exception: ex
            @warnings << :verification_reset_failed
          end

          force_clear_verification!
        end

        # True when a second `accounts` row could share the new address. The
        # wrapper's external_id-keyed write can no longer touch such a row
        # (#3916); this predicate now routes those paths straight to the
        # row-scoped clear — see reset_verification for the rationale.
        def sibling_row_possible?
          @warnings.include?(:new_address_held_by_closed_account) ||
            @warnings.include?(:sql_collision_probe_failed)
        end

        # Fail-closed fallback for every path where the wrapper did not leave the
        # account unverified. Row-scoped and conditional, so it can only ever
        # REMOVE access: it cannot touch a sibling row sharing the address and it
        # cannot move a CLOSED account back to Unverified.
        # @return [Symbol] :reset | :still_verified
        def force_clear_verification!
          sql   = clear_auth_row_verification!
          redis = clear_customer_verification!

          if sql == :failed || redis == :failed
            @warnings << :verification_still_set
            return :still_verified
          end

          return :reset if sql == :unchanged && redis == :unchanged

          @warnings << :verification_force_cleared
          # The wrapper never got far enough to record its own verb, and a
          # verification state change with no event is a hole in the trail. Same
          # verb and shape the wrapper would have emitted (epic #20 CONTRACT 4).
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: 'customer.set_verification',
            target: @customer.extid,
            result: :success,
            detail: { verified: false, forced: true },
          )
          :reset
        end

        # @return [Symbol] :unchanged | :cleared | :failed
        def clear_auth_row_verification!
          db = connection
          return :unchanged unless db

          account_id = auth_account_id(db)
          return :unchanged unless account_id

          rows = db.transaction do
            db[:accounts]
              .where(id: account_id, status_id: AccountStatuses::VERIFIED)
              .update(status_id: AccountStatuses::UNVERIFIED, updated_at: Sequel::CURRENT_TIMESTAMP)
          end
          rows.to_i.positive? ? :cleared : :unchanged
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] forced verification clear failed (SQL)',
            extid: @customer.extid,
            exception: ex
          :failed
        end

        # @return [Symbol] :unchanged | :cleared | :failed
        def clear_customer_verification!
          # Decided on the PERSISTED field, never `@customer.verified?`. The
          # wrapper assigns the attribute before saving
          # (set_customer_verification.rb:112-116), so when that save raises the
          # in-memory flag already reads false while the datastore still holds
          # 'true' — precisely the state this fallback exists to clear. Reading
          # memory here would turn the fallback into a no-op and report a reset
          # that never happened.
          return :unchanged unless stored_verified?

          @customer.verified    = false
          @customer.verified_by = nil
          @customer.save
          :cleared
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] forced verification clear failed (Redis)',
            extid: @customer.extid,
            exception: ex
          :failed
        end

        # The verified flag as the datastore holds it, independent of any
        # in-memory assignment. Matches the model's own authority
        # (Customer#verified? is `verified == 'true'`, status.rb:46), so an
        # unset field reads as NOT verified and no needless clear is recorded.
        # A RAISED read fails closed — treated as still set so the clear runs.
        # @return [Boolean]
        def stored_verified?
          @customer.hget('verified').to_s == 'true'
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] stored verification read failed',
            extid: @customer.extid,
            exception: ex
          true
        end

        # Does the AUTHORITATIVE login gate still say Verified? Consulted only on
        # the wrapper's :no_change path. Fails CLOSED: an unanswerable probe is
        # treated as "may still be verified" so the forced clear runs.
        def auth_row_verified?
          db = connection
          return false unless db

          account_id = auth_account_id(db)
          return false unless account_id

          row = db[:accounts].where(id: account_id).select(:status_id).first
          !row.nil? && row[:status_id] == AccountStatuses::VERIFIED
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] verification status probe failed',
            extid: @customer.extid,
            exception: ex
          @warnings << :verification_probe_failed
          true
        end

        # Read-only observations the operator must see but that this op must NOT
        # act on. Runs once, before any mutation (warn_if_invites_orphaned reads
        # the OLD address off the customer record).
        def preflight_warnings
          return if @preflight_done

          @preflight_done = true
          warn_if_suppressed
          warn_if_invites_orphaned
        end

        # A NEW address already on the suppression list silently kills every future
        # notification to this account — including the change notice itself.
        def warn_if_suppressed
          return unless defined?(Onetime::EmailSuppression)
          return unless Onetime::EmailSuppression.suppressed?(@new_email)

          @warnings << :new_address_suppressed
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] suppression probe failed', exception: ex
        end

        # Pending invites addressed to the OLD address become permanently
        # unacceptable (`accept!` raises 'Email mismatch',
        # organization_membership.rb:331-334). Report; NEVER rewrite invited_email.
        def warn_if_invites_orphaned
          old_email = @customer.email.to_s
          return if old_email.empty?

          orphaned = organizations.any? do |org|
            !Onetime::OrganizationMembership.find_pending_by_email(org, old_email).nil?
          end
          @warnings << :pending_invitations_orphaned if orphaned
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] pending-invite probe failed', exception: ex
        end

        # D36: BOTH addresses. The old address is the security-relevant one; the
        # new address gets a copy so the account holder sees the change land.
        def send_notifications(old_email)
          return unless @notify

          locale = resolve_locale

          enqueue_change_notice(old_email, locale, recipient: old_email)
          enqueue_change_notice(old_email, locale, recipient: @new_email)
        end

        def enqueue_change_notice(old_email, locale, recipient:)
          Onetime::Jobs::Publisher.enqueue_email(
            :email_changed,
            {
              old_email: old_email,
              new_email: @new_email,
              recipient: recipient,
              locale: locale,
            },
            fallback: :async_thread,
          )
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] change notification failed', exception: ex
          @warnings << :notification_failed
        end

        # Blank ("") locales are truthy and slip past a bare `||`; treat as missing.
        def resolve_locale
          locale = @customer.locale.to_s
          locale = OT.default_locale.to_s if locale.strip.empty?
          locale
        end

        # -------------------------------------------------------------- results

        # The customer may be nil/anonymous on the :not_found path, so the target
        # falls back to the shared UNKNOWN sentinel rather than an empty string.
        def failure_target
          extid = (@customer.respond_to?(:extid) ? @customer.extid : nil).to_s
          extid.empty? ? Onetime::AuditedFailure::UNKNOWN : extid
        end

        # One OBSERVATION per preview (#4337), on the budgeted access trail.
        # Same verb and target as the applied event, and — like every other
        # event this op writes — OBSCURED addresses only; `result: 'preview'`
        # and `dry_run: true` distinguish it from the apply that may follow.
        def record_preview_event(old_email, org_count)
          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: failure_target,
            result: 'preview',
            detail: {
              dry_run: true,
              from: OT::Utils.obscure_email(old_email.to_s),
              to: OT::Utils.obscure_email(@new_email.to_s),
              orgs: org_count,
            },
          )
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] preview audit failed', exception: ex
        end

        # A no-change attempt (#4337). This op is the highest-value
        # account-takeover primitive an operator has, so verb-filter
        # completeness matters MOST here: asking to change an address to
        # itself carries less intent than the other no-change verbs, but a
        # `:no_change` answer also CONFIRMS the account currently holds the
        # requested address — which makes a repeated same-address probe
        # exactly the pattern the trail must not go quiet on. Split by intent
        # like the entitlement ops: a LIVE call is a mutation attempt
        # (operator trail, `outcome: 'no_change'`, carrying the D41
        # reason/ticket provenance like record_audit does); a dry-run call
        # (the default) stays a preview observation. Obscured addresses only,
        # as in every other event this op writes. NOT fail-closed: nothing
        # moved.
        def record_no_change_event(old_email)
          detail = {
            outcome: 'no_change',
            from: OT::Utils.obscure_email(old_email.to_s),
            to: OT::Utils.obscure_email(@new_email.to_s),
          }

          if @dry_run
            Onetime::ColonelAuditEvent.record_access(
              actor: @actor,
              verb: AUDIT_VERB,
              target: failure_target,
              result: 'preview',
              detail: detail.merge(dry_run: true),
            )
            return
          end

          detail[:reason] = @reason.to_s unless @reason.to_s.strip.empty?
          detail[:ticket] = @ticket.to_s unless @ticket.to_s.strip.empty?

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: failure_target,
            result: :success,
            detail: detail,
          )
        end

        # Same verb/target/actor as the success event; obscured addresses only,
        # exactly like record_audit. Best-effort: never break the op.
        def record_refusal(status, old_email)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: failure_target,
            result: :failure,
            detail: {
              reason: status.to_s,
              from: OT::Utils.obscure_email(old_email.to_s),
              to: OT::Utils.obscure_email(@new_email.to_s),
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] refusal audit failed', exception: ex
        end

        def failure(status)
          record_refusal(status, @customer.respond_to?(:email) ? @customer.email : nil) if
            REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            extid: @customer.respond_to?(:extid) ? @customer.extid : nil,
            from: @customer.respond_to?(:email) ? @customer.email : nil,
            to: @new_email,
            dry_run: @dry_run,
            auth_row_updated: false,
            orgs_reindexed: 0,
            sessions_revoked: false,
            verification_reset: false,
            warnings: @warnings.uniq,
          )
        end

        # `orgs:` on a :planned result is the WOULD-BE count, not work done.
        def terminal(status, old_email, orgs: 0)
          record_refusal(status, old_email) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            extid: @customer.extid,
            from: old_email,
            to: @new_email,
            dry_run: @dry_run,
            auth_row_updated: false,
            orgs_reindexed: orgs,
            sessions_revoked: false,
            verification_reset: false,
            warnings: @warnings.uniq,
          )
        end

        # SQL committed, Redis did not complete. Compensate ONLY when the Customer
        # hash never took the new address — otherwise both authoritative stores
        # already agree and a write-back would create the drift it prevents.
        def partial(old_email, auth_row_updated, customer_committed, exception)
          auth_logger.error '[customer.change_email] Redis phase failed after SQL commit',
            extid: @customer.extid,
            exception: exception

          rolled_back        = false
          sessions_revoked   = false
          verification_state = :skipped
          if auth_row_updated && !customer_committed
            rolled_back = compensate_auth_row!(old_email)
            @warnings << (rolled_back ? :auth_row_rolled_back : :auth_row_rollback_failed)
          elsif customer_committed
            # Authoritative stores agree on the NEW address; only secondary
            # indexes are behind. `customers doctor` repairs those.
            @warnings << :secondary_writes_incomplete

            # The swap LANDED in this sub-case, so the follow-up work is owed in
            # FULL, exactly as it is on :success — same three calls, same order,
            # same `require_verification` gate. Returning without it would drop
            # the "an email change revokes every session" property on precisely
            # the messy path, leave the account holder with no notice of a change
            # that stuck, and — worst of the three — leave the account flagged
            # VERIFIED on an address nobody has proven ownership of, which is the
            # exact state `require_verification` exists to prevent. All three
            # already swallow their own failures into warnings.
            sessions_revoked   = revoke_sessions
            verification_state = reset_verification
            send_notifications(old_email)

            # On :success a reset that could not be confirmed downgrades the
            # STATUS to :verification_not_reset. Here the status is already
            # :partial and there is nothing below it, so the WARNING carries the
            # same signal under the same name — the operator reads the identical
            # symbol and owes the identical remediation
            # (`bin/ots customers unverify <extid>`), not just the doctor run
            # :partial asks for on its own.
            @warnings << :verification_not_reset if verification_state == :still_verified
          end

          # The claim taken in `index_claim_race_lost?` is a write, and nothing
          # else rolls it back — the customer never took the address, so the
          # entry points at a record that does not hold it. Released here by
          # compare-and-delete; anything it cannot cleanly release raises
          # `:email_index_claim_orphaned`, which tells the operator to run
          # `customers doctor` (check_email_index detects and repairs exactly
          # this mismatch).
          release_index_claim if @index_claim_created && !customer_committed

          record_audit(:partial, old_email, auth_row_updated && !rolled_back)

          Result.new(
            status: :partial,
            extid: @customer.extid,
            from: old_email,
            to: @new_email,
            dry_run: false,
            auth_row_updated: auth_row_updated && !rolled_back,
            orgs_reindexed: @orgs_reindexed.to_i,
            sessions_revoked: sessions_revoked,
            verification_reset: verification_state == :reset,
            warnings: @warnings.uniq,
          )
        end

        # Undo of our own HSETNX claim, by the compare-and-delete above. Only
        # ever reached when WE created the entry AND the Customer hash never took
        # the address, so the entry points at a record that does not hold it.
        #
        # ANY outcome other than "we deleted our own entry" warns: a superseded
        # field means someone else's blind HSET landed on top of a claim we were
        # about to abandon, which is exactly the state `customers doctor`
        # check_email_index reconciles. Staying silent there is what leaves that
        # account unindexed with nobody told to run it.
        def release_index_claim
          index    = Onetime::Customer.email_index
          released = index.dbclient.eval(
            RELEASE_INDEX_CLAIM_SCRIPT,
            keys: [index.dbkey],
            argv: [@new_email.to_s, @customer.objid.to_s],
          )
          return if released.to_i == 1

          auth_logger.warn '[customer.change_email] index claim no longer ours; left in place',
            extid: @customer.extid
          @warnings << :email_index_claim_orphaned
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] orphaned index claim release failed',
            extid: @customer.extid,
            exception: ex
          @warnings << :email_index_claim_orphaned
        end

        # EXACTLY ONE event, from the op, obscured addresses only. `:partial` is
        # recorded as a result, not raised past (D38).
        def record_audit(result, old_email, auth_row_updated)
          detail          = {
            from: OT::Utils.obscure_email(old_email),
            to: OT::Utils.obscure_email(@new_email),
            auth_row_updated: auth_row_updated,
            orgs_reindexed: @orgs_reindexed.to_i,
            require_verification: @require_verification,
            warnings: @warnings.uniq,
          }
          # D41: optional operator provenance — this is the highest-value
          # account-takeover primitive an operator has, and without these the
          # trail records only actor='cli'.
          detail[:reason] = @reason.to_s unless @reason.to_s.strip.empty?
          detail[:ticket] = @ticket.to_s unless @ticket.to_s.strip.empty?

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: result,
            detail: detail,
          )
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end

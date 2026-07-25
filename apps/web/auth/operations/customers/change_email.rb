# apps/web/auth/operations/customers/change_email.rb
#
# frozen_string_literal: true

# Loaded from the auth app AND from the CLI (which runs outside the auth app's
# autoloader), so every dependency is required explicitly.
require 'onetime/models/admin_audit_event'
require 'onetime/jobs/publisher'
require 'onetime/operations/sessions/revoke_all_for_customer'
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
      # is a real hazard, because `SetCustomerVerification#update_rodauth_account!`
      # keys on `where(email:)` and would then update TWO rows. So a closed-account
      # holder is treated as `:email_taken` unless the caller explicitly passes
      # `allow_closed_account_reuse: true`.
      #
      # ## KNOWN, UNCLOSED GAP: simple mode has no uniqueness guard at all
      #
      # In full mode the partial unique index is a real guard — a lost TOCTOU race
      # surfaces as `Sequel::UniqueConstraintViolation`, which we rescue and map to
      # `:email_taken`. In SIMPLE mode there is no SQL at all, and the Familia
      # re-key (`update_in_class_email_index`, unique_index_generators.rb:470-483)
      # is a blind `MULTI` of `HDEL old` + `HSET new` — NOT a compare-and-set. A
      # concurrent signup that claims the address between our check and our write
      # has its index entry SILENTLY STOLEN. Familia exposes
      # `guard_unique_email_index!` but it is a plain read-then-raise, so it
      # narrows the window without closing it. Closing it needs a Lua CAS (cf. the
      # HSETNX-on-declared-field trap already known in this codebase). We re-check
      # immediately before the write to narrow the window and we do not pretend to
      # have closed it.
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

        AUDIT_VERB = 'customer.change_email'

        # Rodauth account statuses (migrations/001_initial.rb:15-19). Only 1 and 2
        # are covered by the partial unique index on accounts.email.
        STATUS_UNVERIFIED = 1
        STATUS_VERIFIED   = 2
        STATUS_CLOSED     = 3
        INDEXED_STATUSES  = [STATUS_UNVERIFIED, STATUS_VERIFIED].freeze

        # @!attribute status [r]
        #   @return [Symbol] one of:
        #     :planned       — dry run; nothing mutated, nothing audited
        #     :success       — both authoritative stores hold the new address
        #     :no_change     — normalized new address equals the current one
        #     :not_found     — no usable customer (nil / anonymous / no email)
        #     :invalid_email — new address failed format validation
        #     :email_taken   — another account holds the address (Redis, SQL, or
        #                      the unique constraint itself)
        #     :partial       — SQL committed but the Redis side did not complete;
        #                      see `warnings` for which way the drift runs
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
          return terminal(:no_change, old_email) if OT::Utils.normalize_email(old_email) == @new_email

          taken = collision_status
          return terminal(taken, old_email) if taken

          # Read-only observations, computed BEFORE any mutation (they read the
          # OLD address) so a dry run and an apply surface the same list.
          preflight_warnings

          # DRY RUN: preview only. Mutate nothing, audit nothing.
          return terminal(:planned, old_email, orgs: organizations.size) if @dry_run

          # --- 1. SQL FIRST (transactional). On failure Redis is untouched. ---
          begin
            auth_row_updated = update_auth_row!
          rescue StandardError => ex
            return terminal(:email_taken, old_email) if unique_violation?(ex)

            raise
          end

          # Simple mode has no SQL guard at all, so re-read the index as LATE as
          # possible — the last statement before the first Redis write. This
          # narrows the race; it does not close it (see class docs).
          return terminal(:email_taken, old_email) if simple_mode_race_lost?

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

          # --- 3. BEST-EFFORT FOLLOW-UP (never invalidates the swap). ---
          sessions_revoked   = revoke_sessions
          verification_reset = reset_verification
          send_notifications(old_email)

          record_audit(:success, old_email, auth_row_updated)

          OT.info "[customer.change_email] #{@customer.extid} " \
                  "#{OT::Utils.obscure_email(old_email)} -> #{OT::Utils.obscure_email(@new_email)} " \
                  "auth_row=#{auth_row_updated} orgs=#{@orgs_reindexed} warnings=#{@warnings.inspect}"

          Result.new(
            status: :success,
            extid: @customer.extid,
            from: old_email,
            to: @new_email,
            dry_run: false,
            auth_row_updated: auth_row_updated,
            orgs_reindexed: @orgs_reindexed,
            sessions_revoked: sessions_revoked,
            verification_reset: verification_reset,
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
          return :email_taken if others.any? { |row| INDEXED_STATUSES.include?(row[:status_id]) }

          # Only CLOSED holders remain: invisible to the unique index AND to
          # Customer.email_exists?, so the write WOULD succeed and leave two rows
          # sharing an address that `where(email:)` callers update in bulk.
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

        # Simple mode only: a last-moment re-read of the global email index. It
        # NARROWS the window between the collision check and the blind MULTI
        # re-key; it does NOT close it. Do not mistake it for a CAS.
        # Returns false in full mode — there the SQL unique constraint is the
        # real guard and its violation is rescued on the UPDATE.
        def simple_mode_race_lost?
          return false if connection

          redis_holder_conflict?
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

          Onetime::Operations::Sessions::RevokeAllForCustomer.new(
            custid: @customer.extid,
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
        # Best-effort: the email swap has already committed, so a raise here must
        # not destroy the audit of a change that DID happen.
        # @return [Boolean]
        def reset_verification
          return false unless @require_verification

          result = Auth::Operations::Customers::SetVerification.new(
            customer: @customer,
            verified: false,
            actor: @actor,
            verified_by: nil,
            db: @db,
          ).call
          result == :success
        rescue StandardError => ex
          auth_logger.error '[customer.change_email] verification reset failed',
            extid: @customer.extid,
            exception: ex
          @warnings << :verification_reset_failed
          false
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

        def failure(status)
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

          rolled_back = false
          if auth_row_updated && !customer_committed
            rolled_back = compensate_auth_row!(old_email)
            @warnings << (rolled_back ? :auth_row_rolled_back : :auth_row_rollback_failed)
          elsif customer_committed
            # Authoritative stores agree on the NEW address; only secondary
            # indexes are behind. `customers doctor` repairs those.
            @warnings << :secondary_writes_incomplete
          end

          record_audit(:partial, old_email, auth_row_updated && !rolled_back)

          Result.new(
            status: :partial,
            extid: @customer.extid,
            from: old_email,
            to: @new_email,
            dry_run: false,
            auth_row_updated: auth_row_updated && !rolled_back,
            orgs_reindexed: @orgs_reindexed.to_i,
            sessions_revoked: false,
            verification_reset: false,
            warnings: @warnings.uniq,
          )
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

          Onetime::AdminAuditEvent.record(
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

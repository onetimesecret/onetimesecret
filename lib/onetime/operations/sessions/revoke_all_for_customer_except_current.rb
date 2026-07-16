# lib/onetime/operations/sessions/revoke_all_for_customer_except_current.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/models/session_metadata'

module Onetime
  module Operations
    module Sessions
      # Revoke a customer's Redis session blobs, OPTIONALLY preserving one current
      # session — the self-service credential-change variant of {RevokeAllForCustomer}
      # (security finding M-2: sessions must not survive a password change/reset).
      #
      # ## Why a separate op from {RevokeAllForCustomer}
      #
      # {RevokeAllForCustomer} is the colonel/offboarding primitive: it clears ALL
      # sessions (including the current one), also deletes the Rodauth SQL
      # `account_active_session_keys` rows, and writes an {Onetime::AdminAuditEvent}.
      # None of that fits a user changing their own password:
      #
      #   1. On a self-service PASSWORD CHANGE the user must KEEP the session they
      #      are changing from — RevokeAllForCustomer has no except-current mode.
      #   2. The Rodauth SQL side is handled by the CALLER, not here: change_password
      #      calls the Rodauth `remove_all_active_sessions_except_current` helper
      #      (except-current SQL), and reset_password already clears those rows via
      #      Rodauth's own `clear_tokens(:reset_password)`. Touching the auth SQL DB
      #      from inside the reset transaction would be redundant and risks a lock
      #      wait, so this op is deliberately REDIS-ONLY.
      #   3. A self-service revoke is an auth-log event (the caller logs it via
      #      Auth::Logging), NOT an admin-audit-trail event — so no AdminAuditEvent
      #      is written here, keeping the colonel audit view free of self-service
      #      noise.
      #
      # ## What actually logs the user out
      #
      # A session dies by deleting the encrypted `session:<sid>` Redis blob — the
      # store BaseSessionAuthStrategy authenticates against, i.e. the REAL app auth
      # gate. (The Rodauth SQL table only gates /auth/* routes; clearing it alone is
      # necessary-but-insufficient, which is the core of M-2.) Two mechanisms, in
      # order of trust, mirror {RevokeAllForCustomer}:
      #
      #   a. GUARANTEED — every sid in Customer#active_sessions is deleted directly
      #      (exact, uncapped), EXCEPT +except_session_id+.
      #   b. BEST-EFFORT — a bounded {Store.scan_keys} sweep deletes genuinely
      #      untracked (pre-sidecar) blobs whose identity matches the customer, again
      #      skipping +except_session_id+. Closes the sidecar backfill gap within the
      #      scan cap; +scan_capped+ is surfaced when the sweep truncates.
      #
      # ## +scan_untracked:+ — keeping the SCAN off the request/transaction path
      #
      # Mechanism (b) is a bounded keyspace SCAN plus a Redis GET + AES-256-GCM
      # decrypt per candidate. On a large keyspace (anonymous sessions dominate a
      # ~200k-account deployment) that costs hundreds of ms. The password hooks
      # invoke this op INSIDE Rodauth's open SQL transaction, so running (b) there
      # would pin a pooled connection + hold row locks for the scan's duration — a
      # burst of resets risks pool exhaustion and lock contention on unrelated auth.
      # Pass +scan_untracked: false+ (the password hooks do) to run the GUARANTEED
      # tracked kill ONLY and skip the sweep. That still revokes every post-sidecar
      # session; it only forgoes mopping up transient pre-sidecar legacy blobs, which
      # self-expire within the 24h blob TTL. Default stays TRUE so offboarding/colonel
      # callers keep the full sweep.
      #
      # The preserved session's blob, sidecar, and index entry are left fully intact.
      #
      # Stateless, single `#call`, returns an immutable {Result}. Best-effort by
      # contract: a missing customer degrades to a zero-count revoke rather than
      # raising (callers wrap it in ErrorHandler.safe_execute regardless).
      class RevokeAllForCustomerExceptCurrent
        # Session-data identity fields matched against the target's extid during the
        # best-effort untracked sweep. Deliberately the same narrow set
        # {RevokeAllForCustomer} uses (extid only) — never account_id/email — so the
        # sweep matches by external identity exactly.
        IDENTITY_FIELDS = %w[external_id account_external_id].freeze

        # @!attribute revoked [r] Boolean always true on a completed call
        # @!attribute blobs_deleted [r] Integer live session blobs deleted (tracked
        #   kills + untracked sweep hits), NEVER counting the preserved session
        # @!attribute untracked_deleted [r] Integer of those blobs NOT in the sidecar
        #   index (pre-sidecar sessions the best-effort scan swept up)
        # @!attribute scan_capped [r] Boolean the untracked sweep hit {Store::MAX_SCAN}
        #   — an untracked pre-sidecar session MAY have been missed (tracked kills are
        #   unaffected; they never touch the scan)
        Result = Data.define(:revoked, :blobs_deleted, :untracked_deleted, :scan_capped)

        # @param custid [String] the target customer (extid/email/objid).
        # @param except_session_id [String, nil] the bare session id to PRESERVE
        #   (the caller's current session). nil/'' preserves nothing → revoke ALL.
        # @param scan_untracked [Boolean] run the best-effort untracked keyspace
        #   sweep (mechanism b). Default TRUE. The password hooks pass FALSE to keep
        #   the SCAN + per-candidate decrypt out of Rodauth's open SQL transaction;
        #   the guaranteed tracked kill (a) is unaffected either way.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(custid:, except_session_id: nil, scan_untracked: true, dbclient: nil)
          @custid            = custid
          # Normalize to a string so the `sid == @except_session_id` guards are
          # type-stable; nil becomes '' which no real sid ever equals → revoke ALL.
          @except_session_id = except_session_id.to_s
          @scan_untracked    = scan_untracked
          @dbclient          = dbclient
        end

        # @return [Result]
        def call
          db       = @dbclient || Familia.dbclient
          customer = load_customer

          return zero_result if customer.nil?

          # Snapshot the index BEFORE we tidy it — drives the guaranteed kill and
          # the tracked/untracked classification.
          tracked     = customer.active_sessions.revrange(0, -1)
          tracked_set = tracked.to_set

          # (a) GUARANTEED: delete each tracked blob directly, skipping current.
          tracked_deleted                = purge_tracked(db, tracked)
          # (b) BEST-EFFORT: sweep the keyspace for untracked blobs, skipping current.
          #     Gated by scan_untracked so the password hooks can keep this SCAN out
          #     of the open SQL transaction (see class docs).
          untracked_deleted, scan_capped =
            @scan_untracked ? purge_untracked(db, customer, tracked_set) : [0, false]
          # (c) Tidy metadata for the sessions we actually revoked (never current).
          tidy_sidecars(customer, tracked)

          Result.new(
            revoked: true,
            blobs_deleted: tracked_deleted + untracked_deleted,
            untracked_deleted: untracked_deleted,
            scan_capped: scan_capped,
          )
        end

        private

        def zero_result
          Result.new(revoked: true, blobs_deleted: 0, untracked_deleted: 0, scan_capped: false)
        end

        # GUARANTEED kill: delete each tracked sid's live blob directly, EXCEPT the
        # preserved current session. The sids are, by construction, this customer's,
        # so no identity check is needed. Exact + uncapped. Returns the count that
        # had a live blob and was deleted.
        #
        # @return [Integer]
        def purge_tracked(db, tracked)
          tracked.count do |sid|
            next false if sid == @except_session_id # keep the current session

            key = Store.find_key(db, sid)
            next false unless key

            db.del(key)
            true
          end
        end

        # BEST-EFFORT sweep for genuinely UNTRACKED (pre-sidecar) blobs whose identity
        # matches the customer, skipping already-killed tracked sids AND the preserved
        # current session. A blank extid would match every anonymous session, so bail
        # before scanning if we cannot identify the target. Returns [count, capped].
        #
        # @return [Array(Integer, Boolean)]
        def purge_untracked(db, customer, tracked_set)
          extid = customer.extid.to_s
          return [0, false] if extid.empty?

          codec   = Onetime::SessionCodec.from_config
          keys    = Store.scan_keys(db)
          deleted = 0

          keys.each do |key|
            sid = Store.extract_id(key)
            next if sid == @except_session_id     # keep the current session
            next if tracked_set.include?(sid)     # already handled in purge_tracked

            data = Store.load_data(db, key, codec: codec)
            next unless data.is_a?(Hash)
            next unless IDENTITY_FIELDS.any? { |f| data[f].to_s == extid }

            db.del(key)
            deleted += 1
          end

          [deleted, keys.size >= Store::MAX_SCAN]
        end

        # Destroy the sidecar and drop the index entry for every REVOKED sid (the
        # current session, if preserved, keeps both). Blobs are already gone; this
        # only reconciles metadata. Uses per-sid remove (not index clear) so the
        # preserved session stays tracked.
        def tidy_sidecars(customer, tracked)
          revoked = tracked.reject { |sid| sid == @except_session_id }
          revoked.each do |sid|
            Onetime::SessionMetadata.load(sid)&.destroy!
            customer.active_sessions.remove(sid)
          end
        end

        # Same resolution as the sibling ops: extid → email → objid. nil is tolerated
        # — a missing customer yields a zero-count revoke.
        def load_customer
          customer = Onetime::Customer.load_by_extid_or_email(@custid) ||
                     Onetime::Customer.load(@custid)
          return nil unless customer&.exists?

          customer
        end
      end
    end
  end
end

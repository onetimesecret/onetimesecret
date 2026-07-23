# lib/onetime/operations/sessions/revoke_all_for_customer_except_current.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/session/sidecar'
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
      # ## +honor_credential_watermark:+ — the async sweep must not kill fresh sessions
      #
      # The async full sweep (#3810) runs SECONDS after the credential change, not
      # inside it. By the time the worker picks up the message, sessions
      # authenticated AFTER the change legitimately exist: the rotated current
      # session, or a fresh post-reset login. Killing those would log the user
      # straight back out of the session the credential change just established.
      # With the flag on, `Customer#last_password_update` acts as a watermark:
      # any blob whose `authenticated_at` is STRICTLY AFTER it is SPARED (blob,
      # sidecar, and index entry all kept, like the preserved current session). A
      # blob authenticated exactly AT the watermark is a same-second pre-change
      # session and is REVOKED, mirroring the auth-time `<=` rejection. A blob with
      # a missing/nil `authenticated_at` coerces to 0 and is deleted whenever a
      # watermark is in force — fail-secure, since only a stale legacy blob lacks
      # the stamp. The flag defaults to FALSE (byte-for-byte historic behavior),
      # and a nil/empty/zero `last_password_update` degrades to the same.
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
        # @param honor_credential_watermark [Boolean] spare blobs authenticated
        #   STRICTLY AFTER `Customer#last_password_update` (see class docs). Default
        #   FALSE. The async sweep worker passes TRUE; with a nil/empty/zero
        #   watermark the flag degrades to the unguarded revoke.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(custid:, except_session_id: nil, scan_untracked: true,
                       honor_credential_watermark: false, dbclient: nil)
          @custid                     = custid
          # Normalize to a string so the `sid == @except_session_id` guards are
          # type-stable; nil becomes '' which no real sid ever equals → revoke ALL.
          @except_session_id          = except_session_id.to_s
          @scan_untracked             = scan_untracked
          @honor_credential_watermark = honor_credential_watermark
          @dbclient                   = dbclient
        end

        # @return [Result]
        def call
          db       = @dbclient || Familia.dbclient
          customer = load_customer

          return zero_result if customer.nil?

          # 0 when the caller didn't opt in OR the customer has no usable stamp —
          # both degrade to the historic unguarded revoke (see class docs).
          watermark = credential_watermark(customer)

          # Snapshot the index BEFORE we tidy it — drives the guaranteed kill and
          # the tracked/untracked classification.
          tracked     = customer.active_sessions.revrange(0, -1)
          tracked_set = tracked.to_set

          # (a) GUARANTEED: delete each tracked blob directly, skipping current
          #     and (when a watermark is active) post-credential-change sessions.
          tracked_deleted, spared        = purge_tracked(db, tracked, watermark)
          # (b) BEST-EFFORT: sweep the keyspace for untracked blobs, skipping current.
          #     Gated by scan_untracked so the password hooks can keep this SCAN out
          #     of the open SQL transaction (see class docs).
          untracked_deleted, scan_capped =
            @scan_untracked ? purge_untracked(db, customer, tracked_set, watermark) : [0, false]
          # (c) Tidy metadata for the sessions we actually revoked (never current,
          #     never the watermark-spared ones — those stay fully tracked).
          tidy_sidecars(customer, tracked, spared)

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
        # preserved current session and any blob the credential watermark spares.
        # The sids are, by construction, this customer's, so no identity check is
        # needed. Exact + uncapped. The per-blob GET + decrypt happens ONLY when a
        # watermark is active, so the default path stays byte-for-byte the historic
        # delete. Returns [deleted_count, spared_sids].
        #
        # @return [Array(Integer, Array<String>)]
        def purge_tracked(db, tracked, watermark)
          codec   = watermark.positive? ? Onetime::SessionCodec.from_config : nil
          spared  = []
          deleted = tracked.count do |sid|
            next false if sid == @except_session_id # keep the current session

            key = Store.find_key(db, sid)
            next false unless key

            # Watermark guard (see class docs): a blob authenticated STRICTLY
            # AFTER the credential change is a legitimate post-change session —
            # spare it.
            if watermark.positive? && spared_by_watermark?(Store.load_data(db, key, codec: codec), watermark)
              spared << sid
              next false
            end

            db.del(key)
            # Sidecar purge runs ONLY on this deleted branch: the preserved
            # current session and any watermark-spared session stay fully
            # alive, per-value keys included (killing e.g. a live
            # awaiting_mfa/domain_context out from under a spared session
            # would corrupt the very session this op promises to keep).
            Onetime::SessionSidecar.purge(sid, dbclient: db)
            true
          end
          [deleted, spared]
        end

        # BEST-EFFORT sweep for genuinely UNTRACKED (pre-sidecar) blobs whose identity
        # matches the customer, skipping already-killed tracked sids AND the preserved
        # current session. A blank extid would match every anonymous session, so bail
        # before scanning if we cannot identify the target. Returns [count, capped].
        #
        # @return [Array(Integer, Boolean)]
        def purge_untracked(db, customer, tracked_set, watermark)
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
            # Watermark guard (see class docs): spare post-credential-change blobs.
            next if watermark.positive? && spared_by_watermark?(data, watermark)

            db.del(key)
            # Deleted-blob branch only — current/spared sids never reach here,
            # so their per-value sidecar keys survive with them.
            Onetime::SessionSidecar.purge(sid, dbclient: db)
            deleted += 1
          end

          [deleted, keys.size >= Store::MAX_SCAN]
        end

        # Destroy the sidecar and drop the index entry for every REVOKED sid (the
        # current session, if preserved, keeps both — as does any watermark-spared
        # sid, whose session stays fully alive). Blobs are already gone; this only
        # reconciles metadata. Uses per-sid remove (not index clear) so the
        # preserved sessions stay tracked.
        def tidy_sidecars(customer, tracked, spared)
          spared  = spared.to_set # O(1) membership for the reject below
          revoked = tracked.reject { |sid| sid == @except_session_id || spared.include?(sid) }
          revoked.each do |sid|
            Onetime::SessionMetadata.load(sid)&.destroy!
            customer.active_sessions.remove(sid)
          end
        end

        # Resolve the active credential watermark: the customer's
        # `last_password_update` as a positive epoch-second integer, or 0 when the
        # caller didn't opt in / the stamp is nil, empty, or non-positive. A zero
        # return disables the guard entirely (historic unguarded behavior).
        #
        # @return [Integer]
        def credential_watermark(customer)
          return 0 unless @honor_credential_watermark

          watermark = customer.last_password_update.to_i
          watermark.positive? ? watermark : 0
        end

        # Whether a decoded blob is SPARED by an active watermark: authenticated
        # STRICTLY AFTER the credential change. A blob authenticated exactly at
        # the watermark is NO LONGER spared (it is revoked); only blobs strictly
        # after survive — mirroring the auth-time `<=` rejection, so a same-second
        # pre-change session dies both here and at auth. A missing/nil
        # `authenticated_at` (or an undecodable blob) coerces to 0 → NOT spared —
        # fail-secure, since only a stale legacy blob lacks the stamp.
        def spared_by_watermark?(data, watermark)
          data.is_a?(Hash) && data['authenticated_at'].to_i > watermark
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

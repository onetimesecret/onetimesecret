# lib/onetime/operations/sessions/revoke_all_for_customer.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/models/session_metadata'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Sessions
      # Revoke EVERY session for a customer — the offboarding / account-takeover
      # variant of {RevokeForCustomer} (spec docs/specs/colonel-ui/40-*). Where
      # single-revoke kills one known sid from the sidecar index, this primitive
      # must guarantee the account is fully locked out, so it is deliberately
      # broader (and more expensive) than its sibling in three ways.
      #
      # ## 1. Tracked index is the GUARANTEED kill; the scan is best-effort only
      #
      # A session dies here by deleting the encrypted `session:<sid>` blob
      # (adaptation #1). Two mechanisms, in this order of trust:
      #
      #   a. GUARANTEED — every sid in Customer#active_sessions is deleted directly
      #      via `Store.find_key` + `del` (the exact, UNCAPPED primitive single
      #      revoke uses). These sids are, by construction, this customer's, so no
      #      identity check is needed and no keyspace walk is involved.
      #   b. BEST-EFFORT — a bounded {Store.scan_keys} SCAN then sweeps for
      #      genuinely UNTRACKED blobs (pre-sidecar sessions the index never saw),
      #      decrypting each with the shared {Onetime::SessionCodec} and deleting
      #      those whose identity matches. This closes the sidecar's forward-only
      #      backfill gap — but only within the scan cap.
      #
      # Why (b) is NOT the primary path: {Store::MAX_SCAN} caps the scan at 10k
      # keys in arbitrary slot order, and anonymous CSRF-only sessions dominate the
      # keyspace (Store.rb). At ~200k accounts the cap can be exhausted before the
      # target's blobs are reached — so a scan-first design would leave a tracked,
      # authenticated session LIVE while (c) below destroyed its sidecar, yielding a
      # live-but-invisible session and a silent "0 killed". Killing the tracked set
      # directly makes the revoke cap-proof for every session we can name. When the
      # scan truncates, `scan_capped` is surfaced (Result + audit detail) so a
      # partial untracked sweep is visible, not silent — the pre-sidecar window it
      # targets also closes within the 24h blob TTL after the sidecar deploy.
      #
      # ## 2. Rodauth SQL index cleared (full mode only)
      #
      # Single-revoke leaves the Rodauth `account_active_session_keys` row to
      # self-expire (it only gates Rodauth-mounted routes). Offboarding wants those
      # routes locked IMMEDIATELY, so this op deletes the account's rows directly
      # via Sequel — the ops layer has no bound Rodauth instance, so it cannot call
      # `rodauth.remove_all_active_sessions_for`; it does the same DELETE that
      # Auth::Operations::CloseAccount does. Guarded on the auth DB being present
      # (nil in simple mode → skipped).
      #
      # ## 3. One audit event with counts
      #
      # Exactly one {Onetime::AdminAuditEvent} (`verb: session.revoke_all`, target =
      # the customer), detail carrying the kill counts so the operator (and the
      # trail) sees how total the revoke actually was. Best-effort throughout: a
      # missing customer or a down auth DB degrades to zero-counts, never a raise
      # that leaves the account half-revoked.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class RevokeAllForCustomer
        # Audit verb recorded for every customer-scoped revoke-all.
        AUDIT_VERB = 'session.revoke_all'

        # Session-data identity fields matched against the target's extid.
        IDENTITY_FIELDS = %w[external_id account_external_id].freeze

        # @!attribute revoked [r] Boolean always true on a completed call
        # @!attribute blobs_deleted [r] Integer live session blobs deleted (the logouts;
        #   tracked kills + untracked sweep hits)
        # @!attribute untracked_deleted [r] Integer of those blobs NOT in the sidecar index
        #   (pre-sidecar sessions the best-effort scan swept up)
        # @!attribute rodauth_rows_deleted [r] Integer Rodauth active_session_keys rows
        #   removed (0 in simple mode / when no auth account exists)
        # @!attribute scan_capped [r] Boolean the untracked sweep hit {Store::MAX_SCAN}
        #   — an untracked pre-sidecar session MAY have been missed (tracked kills are
        #   unaffected; they never touch the scan)
        Result = Data.define(:revoked, :blobs_deleted, :untracked_deleted, :rodauth_rows_deleted, :scan_capped)

        # @param custid [String] the target customer (route param; extid/email/objid).
        # @param actor [String, #extid] acting colonel's PUBLIC identity (extid).
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(custid:, actor:, dbclient: nil)
          @custid   = custid
          @actor    = actor
          @dbclient = dbclient
        end

        # @return [Result]
        def call
          db       = @dbclient || Familia.dbclient
          customer = load_customer

          # Snapshot the sidecar index BEFORE we tidy it — it drives both the
          # guaranteed kill and the untracked-vs-tracked classification.
          tracked     = customer ? customer.active_sessions.revrange(0, -1) : []
          tracked_set = tracked.to_set

          # (a) GUARANTEED: delete every tracked blob directly (exact, uncapped).
          tracked_deleted                = purge_tracked(db, tracked)
          # (b) BEST-EFFORT: sweep the keyspace for untracked (pre-sidecar) blobs.
          untracked_deleted, scan_capped = purge_untracked(db, customer, tracked_set)
          # (c) Tidy metadata now that the blobs are gone.
          tidy_sidecars(customer, tracked)
          # (d) Full mode: clear the Rodauth active-session rows.
          rodauth_rows_deleted           = purge_rodauth_rows(customer)

          blobs_deleted = tracked_deleted + untracked_deleted

          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @custid,
            result: :success,
            detail: {
              blobs_deleted: blobs_deleted,
              untracked_deleted: untracked_deleted,
              rodauth_rows_deleted: rodauth_rows_deleted,
              scan_capped: scan_capped,
            },
          )

          Result.new(
            revoked: true,
            blobs_deleted: blobs_deleted,
            untracked_deleted: untracked_deleted,
            rodauth_rows_deleted: rodauth_rows_deleted,
            scan_capped: scan_capped,
          )
        end

        private

        # GUARANTEED kill: delete each tracked sid's live blob directly. The sids
        # are, by construction, this customer's (TrackMetadata only ZADDs their own
        # sessions), so no identity check is needed. Exact + UNCAPPED — the same
        # `Store.find_key` + `del` primitive single-revoke uses — so it can never be
        # defeated by the scan cap. Returns the count that had a live blob.
        #
        # @return [Integer]
        def purge_tracked(db, tracked)
          tracked.count do |sid|
            key = Store.find_key(db, sid)
            next false unless key

            db.del(key)
            true
          end
        end

        # BEST-EFFORT sweep for genuinely UNTRACKED blobs — pre-sidecar sessions the
        # index never saw. Bounded SCAN → decrypt (shared codec, NOT close_account's
        # legacy base64/JSON split, which no longer matches an AES-256-GCM blob) →
        # delete those whose identity matches, SKIPPING tracked sids (already killed
        # in purge_tracked). Returns [count, scan_capped].
        #
        # A blank extid would make `data[f].to_s == ''` match every anonymous
        # session and nuke the keyspace, so bail before scanning if we can't
        # identify the target.
        #
        # @return [Array(Integer, Boolean)]
        def purge_untracked(db, customer, tracked_set)
          return [0, false] if customer.nil?

          extid = customer.extid.to_s
          return [0, false] if extid.empty?

          codec   = Onetime::SessionCodec.from_config
          keys    = Store.scan_keys(db)
          deleted = 0

          keys.each do |key|
            sid = Store.extract_id(key)
            next if tracked_set.include?(sid) # already killed, exactly

            data = Store.load_data(db, key, codec: codec)
            next unless data.is_a?(Hash)
            next unless IDENTITY_FIELDS.any? { |f| data[f].to_s == extid }

            db.del(key)
            deleted += 1
          end

          [deleted, keys.size >= Store::MAX_SCAN]
        end

        # Destroy every sidecar the index knew about, then clear the index. Blobs
        # are already gone (purge_tracked); this only reconciles the metadata.
        def tidy_sidecars(customer, tracked)
          return if customer.nil?

          tracked.each { |sid| Onetime::SessionMetadata.load(sid)&.destroy! }
          customer.active_sessions.clear
        end

        # Delete the account's Rodauth active-session rows (full mode). Returns the
        # row count removed, or 0 when the auth DB is absent (simple mode) or no
        # account maps to this extid. Best-effort: a DB error degrades to 0 rather
        # than aborting a revoke whose blob kill already succeeded — but it is
        # LOGGED distinctly (OT.le below), so a prod failure is visible and not
        # silently indistinguishable from "no rows".
        #
        # Column names verified against Auth::Operations::CloseAccount and
        # Auth::Routes::ActiveSessions: `accounts.external_id`, `accounts.id`, and
        # `account_active_session_keys.account_id`. This path is full-mode-only, so
        # it is covered by inspection, not the (simple-mode) tryout suite.
        #
        # @return [Integer]
        def purge_rodauth_rows(customer)
          return 0 if customer.nil?

          db = auth_db
          return 0 if db.nil?

          account = db[:accounts].where(external_id: customer.extid).first
          return 0 if account.nil?

          db[:account_active_session_keys].where(account_id: account[:id]).delete
        rescue StandardError => ex
          OT.le(
            '[RevokeAllForCustomer] rodauth row purge failed',
            exception: ex,
            custid: @custid,
          )
          0
        end

        # The auth (Rodauth) SQL connection, or nil in simple mode. Auth::Database
        # lives in the auth app; guard on it being loaded so this op stays usable
        # in contexts where the auth stack isn't required.
        def auth_db
          return nil unless defined?(Auth::Database)

          Auth::Database.connection
        end

        # Same resolution as ListForCustomer / RevokeForCustomer: extid → email →
        # objid. nil is tolerated — a missing customer yields a zero-count revoke.
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

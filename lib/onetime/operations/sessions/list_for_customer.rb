# lib/onetime/operations/sessions/list_for_customer.rb
#
# frozen_string_literal: true

require 'onetime/safe_dumpable'
require 'onetime/operations/sessions/store'
require 'onetime/models/session_metadata'

module Onetime
  module Operations
    module Sessions
      # List one customer's sessions from the metadata sidecar — the read half of
      # the per-customer session view (spec docs/specs/colonel-ui/40-*).
      #
      # This is the O(sessions-for-this-user) alternative to the GLOBAL console
      # (Onetime::Operations::Sessions::List), which SCANs + decrypts the whole
      # `session:*` keyspace. Here we read Customer#active_sessions (a sorted set
      # scored by last activity) and resolve each sid to its lightweight
      # {Onetime::SessionMetadata} record — no scan, no decrypt, no blob read.
      #
      # READ-ONLY w.r.t. sessions: it records NO {Onetime::ColonelAuditEvent}
      # (CONTRACT 4 — audit is for mutations). It DOES self-heal against BOTH the
      # sidecar and the live blob, so the console only ever shows sessions that
      # are actually alive:
      #   * sidecar gone (its own TTL / explicit destroy) → ZREM the index member.
      #   * sidecar present but `session:<sid>` blob gone → the session is dead
      #     (the sidecar's 30d TTL outlives the blob's 24h default), so destroy
      #     the orphan sidecar + ZREM the member and hide the row.
      # The blob check is the same no-decrypt EXISTS probe ({Store.find_key}) the
      # revoke path uses — O(patterns) per sid, no SCAN.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class ListForCustomer
        # One listed session: the public {SessionMetadata#safe_dump} projection
        # paired with the internal correlation key drawn from the SAME sidecar
        # read.
        #
        # A plain Ruby 3.2+ {Data} value object, so it carries `#to_h` (full,
        # internal, includes the join key) for internal joins and logging. Its
        # public boundary is {#safe_dump}, exactly as a Horreum model's is: the
        # only shape that may cross an HTTP response is {#safe_dump}, never
        # {#to_h} ({Onetime::SafeDumpable}, ADR-040). Here the projection is a
        # single member that is ITSELF a model safe_dump row, so #safe_dump
        # returns it directly rather than wrapping it.
        #
        # @!attribute session [r] Hash: the SessionMetadata safe_dump row
        # @!attribute active_session_id_hmac [r] String, nil: the value Rodauth
        #   persists in its `session_id` column, for consumers that must join
        #   sidecar rows to Rodauth active-session records. INTERNAL: present in
        #   #to_h, absent from #safe_dump. nil/empty when the sidecar never
        #   stored one (sessions older than the join key).
        Entry = Data.define(:session, :active_session_id_hmac) do
          include Onetime::SafeDumpable

          def safe_dump
            session
          end
        end

        # @!attribute entries [r] Array<Entry> listed sessions, newest-first,
        #   post-prune. The single source of truth; {#sessions} and {#count} are
        #   derived public projections over it, and {#safe_dump} is the public
        #   boundary ({Onetime::SafeDumpable}, ADR-040); {#to_h} exposes the
        #   internal Entry objects and must not cross an HTTP response.
        Result = Data.define(:entries) do
          include Onetime::SafeDumpable

          safe_dump_fields :sessions, :count

          # @return [Array<Hash>] safe_dump rows, newest-first
          def sessions
            entries.map(&:safe_dump)
          end

          # @return [Integer] sessions returned (== sessions.size, post-prune)
          def count
            entries.size
          end
        end

        # Marks a sidecar whose READ failed (transient store error / corrupt
        # record), as distinct from nil = "sidecar demonstrably absent". The
        # distinction is load-bearing: a missing sidecar triggers the self-heal
        # ZREM below, while a failed read must only skip its row — pruning an
        # index member because of a transient failure would silently unlist a
        # live session.
        SIDECAR_READ_FAILED = Module.new.freeze
        private_constant :SIDECAR_READ_FAILED

        # @param custid [String] route param identifying the target customer;
        #   resolved by extid → email → objid (see #call), matching the colonel
        #   customer-detail resolution (get_user_details.rb).
        # @param dbclient [Object, nil] reserved for symmetry with sibling ops;
        #   the Familia models resolve their own connection.
        def initialize(custid:, dbclient: nil)
          @custid   = custid
          @dbclient = dbclient
        end

        # @return [Result]
        def call
          customer = load_customer
          return Result.new(entries: []) if customer.nil?

          db = @dbclient || Familia.dbclient

          # revrange(0, -1) yields members highest-score-first, i.e. newest
          # last-activity first (TrackMetadata scores by last_activity epoch).
          sids = customer.active_sessions.revrange(0, -1)

          # One pipelined round trip for ALL sidecars (Familia load_multi,
          # position-aligned, nil for missing) instead of a serial load per sid.
          metas = load_sidecars(sids)

          entries = sids.each_with_index.filter_map do |sid, idx|
            meta = metas[idx]

            # Sidecar data is supplementary. A transient store failure or corrupt
            # record must not hide otherwise-authoritative session information —
            # and must NOT be mistaken for absence (which would self-heal-prune a
            # live member below). Skip only this row.
            next nil if meta.equal?(SIDECAR_READ_FAILED)

            begin
              if meta.nil?
                # Self-heal: the sidecar is gone (TTL-expired or the blob was
                # revoked out-of-band) but the index still names it. Drop the stale
                # member so the set converges to live sessions only.
                customer.active_sessions.remove(sid)
                next nil
              end

              # Blob-liveness reconcile: the sidecar (30d TTL) outlives the session
              # blob (24h default), so a sid whose `session:<sid>` blob is gone is a
              # DEAD session the sidecar hasn't caught up to. Hide it and converge
              # the sidecar + index. EXISTS-only probe — no decrypt, no SCAN.
              if Store.find_key(db, sid).nil?
                meta.destroy!
                customer.active_sessions.remove(sid)
                next nil
              end
            rescue StandardError
              # Reconciliation is best-effort. A store failure while probing or
              # pruning one stale row must not abort the entire session listing.
              next nil
            end

            Entry.new(
              session: meta.safe_dump,
              active_session_id_hmac: meta.active_session_id_hmac,
            )
          end

          Result.new(entries: entries)
        end

        private

        # Batched sidecar read: one pipelined round trip for every sid
        # ({Familia::Horreum.load_multi}: position-aligned with the input, nil
        # for keys that don't exist — the same per-position contract the old
        # serial loads had).
        #
        # Failure semantics: load_multi materializes every record in one call,
        # so ANY failure inside it (connection error, or one corrupt record
        # raising during instantiation) surfaces as a single batch-level raise.
        # That must not take out the listing where a single bad row previously
        # degraded gracefully — so a batch failure falls back to the legacy
        # per-row loads, where each row's own failure maps to
        # {SIDECAR_READ_FAILED} (row skipped, index member kept) exactly as the
        # old per-row rescue did.
        #
        # @param sids [Array<String>]
        # @return [Array<Onetime::SessionMetadata, nil, SIDECAR_READ_FAILED>]
        def load_sidecars(sids)
          return [] if sids.empty?

          Onetime::SessionMetadata.load_multi(sids)
        rescue StandardError
          sids.map do |sid|
            Onetime::SessionMetadata.load(sid)
          rescue StandardError
            SIDECAR_READ_FAILED
          end
        end

        # Resolve the target customer the same way the colonel customer-detail
        # path does (get_user_details.rb): extid first (every admin surface routes
        # by extid), then email, then objid. A bare Customer.load only resolves
        # the internal objid, so an extid/email would miss.
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

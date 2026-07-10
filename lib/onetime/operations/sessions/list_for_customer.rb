# lib/onetime/operations/sessions/list_for_customer.rb
#
# frozen_string_literal: true

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
      # READ-ONLY w.r.t. sessions: it records NO {Onetime::AdminAuditEvent}
      # (CONTRACT 4 — audit is for mutations). It DOES self-heal the index: a sid
      # whose sidecar has expired/been deleted is ZREM'd from active_sessions so a
      # stale member can't accumulate (the blob can outlive or be deleted
      # independently of the set — see SessionMetadata's population note).
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class ListForCustomer
        # @!attribute sessions [r] Array<Hash> safe_dump rows, newest-first
        # @!attribute count [r] Integer sessions returned (== sessions.size, post-prune)
        Result = Data.define(:sessions, :count)

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
          return Result.new(sessions: [], count: 0) if customer.nil?

          # revrange(0, -1) yields members highest-score-first, i.e. newest
          # last-activity first (TrackMetadata scores by last_activity epoch).
          sids = customer.active_sessions.revrange(0, -1)

          sessions = sids.filter_map do |sid|
            meta = Onetime::SessionMetadata.load(sid)
            if meta.nil?
              # Self-heal: the sidecar is gone (TTL-expired or the blob was
              # revoked out-of-band) but the index still names it. Drop the stale
              # member so the set converges to live sessions only.
              customer.active_sessions.remove(sid)
              next nil
            end

            meta.safe_dump
          end

          Result.new(sessions: sessions, count: sessions.size)
        end

        private

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

# lib/onetime/operations/sessions/inspect_session.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'

module Onetime
  module Operations
    module Sessions
      # Inspect a single session — the SINGLE implementation of the session-inspect
      # verb (epic #40 / D3). The colonel endpoint (`GET /api/colonel/sessions/:id`)
      # and the `bin/ots session inspect` CLI are thin adapters over it.
      #
      # READ-ONLY: records NO {Onetime::AdminAuditEvent} (CONTRACT 4).
      #
      # Stateless, single `#call`, returns an immutable {Result}. A miss (no key for
      # the id, or an empty value) returns `found: false` with nil fields.
      class Inspect
        # @!attribute found [r] Boolean whether a session key was resolved + loaded
        # @!attribute ttl [r] Integer, nil Redis TTL in seconds (-1 no expiry, -2 gone)
        # @!attribute data [r] Hash, nil the full parsed session payload
        Result = Data.define(:found, :session_id, :key, :ttl, :data)

        # @param session_id [String] the bare session id to resolve.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(session_id:, dbclient: nil)
          @session_id = session_id
          @dbclient   = dbclient
        end

        # @return [Result]
        def call
          db  = @dbclient || Familia.dbclient
          key = Store.find_key(db, @session_id)
          return miss unless key

          data = Store.load_data(db, key)
          return miss unless data

          Result.new(
            found: true,
            session_id: @session_id,
            key: key,
            ttl: db.ttl(key),
            data: data,
          )
        end

        private

        def miss
          Result.new(found: false, session_id: @session_id, key: nil, ttl: nil, data: nil)
        end
      end
    end
  end
end

# lib/onetime/operations/sessions/store.rb
#
# frozen_string_literal: true

require 'json'
require 'redis' # for Redis::CommandError in the defensive load_data rescue

module Onetime
  module Operations
    module Sessions
      # Shared session-store primitives — the SINGLE source of the Redis/session
      # key logic that the session admin verbs (List / Inspect / Delete) and the
      # CLI `bin/ots session *` commands are thin adapters over (epic #40 / D3).
      #
      # Before this extraction the key patterns, the JSON-safe loader, and the
      # search matcher lived only inside `Onetime::CLI::SessionHelpers`, so there
      # was no operation, API, or UI — incident response required SSH. This module
      # lifts that capability out; `SessionHelpers` now delegates to it (the CLI is
      # a thin adapter), and the colonel endpoints call the ops that use it.
      #
      # Context-free by contract (lib/onetime/operations/README.md): it knows
      # nothing about HTTP or sessions-as-auth; callers pass the dbclient (or let
      # it default to {Familia.dbclient}, exactly as the CLI did).
      #
      # ## Security note (issue #3498, preserved)
      #
      # {load_data} parses Redis-sourced bytes with JSON.parse, NEVER Marshal.load:
      # Marshal walks (and instantiates) its object graph BEFORE it can raise, so a
      # rescue around it offers no protection against a crafted gadget chain planted
      # at a session key. On any parse failure it returns a bounded `{'_raw' => ...}`
      # fallback. This behaviour is byte-for-byte what `SessionHelpers#load_session_data`
      # guaranteed and what `spec/cli/session_command_security_spec.rb` locks in.
      module Store
        module_function

        # Non-blocking SCAN match for every session key shape (CONTRACT 6 — bounded
        # cursor scan only, never a blocking KEYS on the request path).
        SESSION_SCAN_PATTERN = '*session*'

        # Hard cap on how many session keys a single bounded scan collects, so an
        # unbounded keyspace can never turn one request into an O(all-keys) walk.
        MAX_SCAN = 10_000

        # Common prefixes stripped to recover the bare session id from a key.
        KEY_PREFIX_PATTERN = /^(session:|rack:session:)/

        # The candidate keys a bare session id can live under. Identical to the
        # historic CLI list — order matters (first existing key wins).
        #
        # @param session_id [String]
        # @return [Array<String>]
        def key_patterns(session_id)
          [
            "session:#{session_id}",
            "rack:session:#{session_id}",
            session_id,
            "session:rack:session:#{session_id}",
          ]
        end

        # The first key pattern that exists for this id, or nil. Uses EXISTS only
        # (no blocking scan) — a bounded, O(patterns) probe.
        #
        # @param dbclient [Object] a Redis-like client
        # @param session_id [String]
        # @return [String, nil]
        def find_key(dbclient, session_id)
          key_patterns(session_id).each do |pattern|
            return pattern if dbclient.exists(pattern) > 0
          end
          nil
        end

        # Load + JSON-parse a session value. Returns nil when the key holds nothing,
        # a parsed Hash on success, or a bounded `{'_raw' => ...}` fallback when the
        # bytes are not JSON. NEVER calls Marshal.load (see the security note above).
        #
        # The GET itself is defensive: a non-string key that slipped past the
        # scan filter (e.g. a SET named `session:<sid>:...`, like the colonel
        # entitlement-preview keys) raises WRONGTYPE, and one bad key must never
        # take down a whole listing (QA 2026-07-07: every GET /api/colonel/sessions
        # 500ed while such keys existed). Command-level failures resolve to nil —
        # "no session data here" — while connection errors still propagate.
        #
        # @param dbclient [Object]
        # @param key [String]
        # @return [Hash, nil]
        def load_data(dbclient, key)
          raw_data = begin
            dbclient.get(key)
          rescue Redis::CommandError
            nil
          end
          return nil unless raw_data

          begin
            JSON.parse(raw_data)
          rescue StandardError
            { '_raw' => raw_data[0..200] }
          end
        end

        # Recover the bare session id from a full key.
        #
        # @param key [String]
        # @return [String]
        def extract_id(key)
          key.gsub(KEY_PREFIX_PATTERN, '')
        end

        # Bounded, non-blocking scan of every session key. Uses SCAN (via
        # `scan_each`, the same lazy cursor iterator the historic CLI used — never a
        # blocking KEYS, CONTRACT 6) and stops after at most {MAX_SCAN} keys so an
        # unbounded keyspace can't turn one request into an O(all-keys) walk.
        #
        # Filters to STRING keys server-side (SCAN's TYPE option, Redis 6+):
        # real session values are strings, but the loose `*session*` match also
        # catches non-string keys such as the entitlement-preview SETs
        # (`session:<sid>:entitlement_preview_*`), which would WRONGTYPE on GET.
        # {load_data} stays defensive for anything a filter can't anticipate.
        #
        # @param dbclient [Object]
        # @param pattern [String]
        # @return [Array<String>] the matched keys (scan order, capped)
        def scan_keys(dbclient, pattern: SESSION_SCAN_PATTERN)
          dbclient.scan_each(match: pattern, type: 'string').first(MAX_SCAN)
        end

        # Count session keys via the same bounded, string-typed scan the listing
        # uses. Backs the colonel stats/info `session_count`, which was hardcoded
        # to 0 after session tracking moved to Rack::Session middleware.
        #
        # @param dbclient [Object]
        # @return [Integer]
        def count(dbclient)
          scan_keys(dbclient).size
        end

        # Build a compact, JSON-ready summary of one session for list rows. Raw
        # email is returned (the colonel is fully privileged and the detail view
        # shows it anyway); presentation-layer obscuring — e.g. the CLI `list`
        # formatter — stays in the adapter so the op has one canonical shape.
        #
        # @param session_id [String]
        # @param key [String]
        # @param data [Hash] parsed session data
        # @return [Hash]
        def summarize(session_id, key, data)
          {
            session_id: session_id,
            key: key,
            authenticated: data['authenticated'] ? true : false,
            email: data['email'],
            external_id: data['external_id'] || data['account_external_id'],
            role: data['role'],
            ip_address: data['ip_address'],
            created_at: data['authenticated_at'],
          }
        end

        # Case-insensitive match of a session against a free-text term across the
        # identity fields. Identical predicate to the historic CLI `search`.
        #
        # @param data [Hash]
        # @param term [String]
        # @return [Boolean]
        def matches_search?(data, term)
          needle = term.to_s.downcase
          return false if needle.empty?

          [
            data['email'],
            data['external_id'],
            data['account_external_id'],
          ].compact.any? { |field| field.downcase.include?(needle) }
        end
      end
    end
  end
end

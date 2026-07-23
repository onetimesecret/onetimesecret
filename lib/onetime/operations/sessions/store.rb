# lib/onetime/operations/sessions/store.rb
#
# frozen_string_literal: true

require 'json'
require 'redis' # for Redis::CommandError in the defensive load_data rescue
require 'onetime/session/codec' # canonical decryptor injected into load_data

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
        extend self

        # Non-blocking SCAN match for every session key shape (CONTRACT 6 — bounded
        # cursor scan only, never a blocking KEYS on the request path).
        SESSION_SCAN_PATTERN = '*session*'

        # Hard cap on how many session keys a single bounded scan collects, so an
        # unbounded keyspace can never turn one request into an O(all-keys) walk.
        MAX_SCAN = 10_000

        # Common prefixes stripped to recover the bare session id from a key.
        KEY_PREFIX_PATTERN = /^(session:|rack:session:)/

        # Per-value sidecar keys (Onetime::SessionSidecar, issue #3858):
        # "session:" + a full hex sid + ":" + field. They are STRINGs, so the
        # scan's `type: 'string'` filter alone would sweep them into every
        # `*session*` consumer (listings, counts, revoke sweeps). No legacy
        # blob shape has anything after the sid ({key_patterns}), so this
        # cannot match a blob — including the bare-sid and
        # session:rack:session:<sid> shapes. The sidecar's own sid format
        # guard guarantees every key it creates matches this pattern.
        SIDECAR_KEY_PATTERN = /\Asession:[a-f0-9]{64,}:/

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
        # @param codec [Onetime::SessionCodec, nil] when given, the PRIMARY path:
        #   session values are AES-256-GCM encrypted + HMAC signed
        #   (`base64(...)--hmac`), so a plain JSON.parse always failed and every
        #   session fell through to the `_raw` preview — the colonel console
        #   therefore showed every session, authenticated ones included, as
        #   opaque/Anonymous. Decoding first makes identity fields resolve.
        # @return [Hash, nil]
        def load_data(dbclient, key, codec: nil)
          raw_data = begin
            dbclient.get(key)
          rescue Redis::CommandError
            nil
          end
          return nil unless raw_data

          # Primary: decrypt an authentic session blob to its data hash.
          if codec
            decoded = codec.decode(raw_data)
            return decoded if decoded.is_a?(Hash)
          end

          # Fallback: legacy plaintext-JSON values and anything that is not an
          # authentic session blob. NEVER Marshal.load (see the security note
          # above); non-JSON degrades to a bounded `_raw` preview.
          begin
            JSON.parse(raw_data)
          rescue StandardError
            { '_raw' => raw_data[0..200] }
          end
        end

        # Identity fields that make a session worth listing for incident
        # response. A session with none of these carries no actor — in practice
        # an anonymous visitor session holding only a CSRF token.
        IDENTITY_FIELDS = %w[account_id external_id account_external_id email].freeze

        # Whether a parsed session has any actor identity. False for the
        # CSRF-only anonymous sessions that dominate the keyspace (and for the
        # `_raw` fallback, which has no identity keys either).
        #
        # @param data [Hash]
        # @return [Boolean]
        def identified?(data)
          return false unless data.is_a?(Hash)

          IDENTITY_FIELDS.any? { |f| !data[f].to_s.empty? }
        end

        # Recover the bare session id from a full key. Strips EVERY leading
        # session:/rack:session: prefix, not just one — the legacy
        # `session:rack:session:<sid>` shape ({key_patterns}) nests two, and a
        # single strip would leave `rack:session:<sid>`, which then fails the
        # sidecar sid-format guard so {SessionSidecar.purge} silently no-ops.
        #
        # @param key [String]
        # @return [String]
        def extract_id(key)
          id = key.to_s
          id = id.sub(KEY_PREFIX_PATTERN, '') while id.match?(KEY_PREFIX_PATTERN)
          id
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
        # Sidecar keys ({SIDECAR_KEY_PATTERN}) ARE strings, so they need the
        # client-side reject.
        #
        # {MAX_SCAN} bounds the RAW cursor iterations (the safety property),
        # then the sidecar reject runs — NOT the reverse. Rejecting first and
        # capping the survivors would let a sidecar-dense keyspace pull far more
        # than {MAX_SCAN} keys off the cursor to collect {MAX_SCAN} blobs,
        # reopening the O(all-keys) walk the cap exists to prevent. The
        # consequence: because the reject runs AFTER the cap, the surviving blob
        # count is a floor, so truncation must be judged from the RAW (pre-reject)
        # size — {scan_keys_capped} returns that flag; deriving it from the
        # survivor count (`keys.size >= MAX_SCAN`) would silently under-report a
        # capped scan whenever sidecars filled part of the first {MAX_SCAN} keys.
        # {load_data} stays defensive for anything a filter can't anticipate.
        #
        # @param dbclient [Object]
        # @param pattern [String]
        # @return [Array(Array<String>, Boolean)] the matched non-sidecar keys
        #   (scan order), and whether the raw cursor hit {MAX_SCAN} (truncated)
        def scan_keys_capped(dbclient, pattern: SESSION_SCAN_PATTERN)
          raw = dbclient.scan_each(match: pattern, type: 'string')
                        .lazy
                        .first(MAX_SCAN)
          [raw.reject { |key| key.match?(SIDECAR_KEY_PATTERN) }, raw.size >= MAX_SCAN]
        end

        # The non-sidecar session keys from a bounded scan, dropping the
        # truncation flag — for callers (counts) that don't report capping. See
        # {scan_keys_capped} for the scan semantics and why capping is judged
        # from the raw size, not the returned count.
        #
        # @param dbclient [Object]
        # @param pattern [String]
        # @return [Array<String>] the matched non-sidecar keys (scan order)
        def scan_keys(dbclient, pattern: SESSION_SCAN_PATTERN)
          scan_keys_capped(dbclient, pattern: pattern).first
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
            user_agent: data['user_agent'],
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

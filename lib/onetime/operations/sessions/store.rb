# lib/onetime/operations/sessions/store.rb
#
# frozen_string_literal: true

require 'json'
require 'redis' # for Redis::CommandError in the defensive load_data rescue
require 'onetime/session/codec' # canonical decryptor injected into load_data
require 'onetime/models/session_metadata' # handle_for — the non-bearer session id

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

        # Shape of Onetime::SessionMetadata.handle_for output (HANDLE_LENGTH = 32).
        HANDLE_PATTERN = /\A[0-9a-f]{32}\z/

        # Shortest handle prefix {matches_search?} will treat as a handle needle.
        # Below this a hex-looking term is far more likely to be part of an extid
        # or an email than a handle the operator copied off a row.
        HANDLE_SEARCH_PATTERN = /\A[0-9a-f]{4,32}\z/

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
        # Per-value sidecar keys (Onetime::SessionSidecar) ARE strings, but live
        # under `sidecar:<sid>:<field>` — outside this match by construction
        # (the prefix must never contain "session"; see SessionSidecar.key_for)
        # — so no client-side reject is needed and `keys.size >= MAX_SCAN`
        # remains an exact truncation signal for callers that report capping.
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
        # `session_handle` is the ONLY identifier safe to serialize (#4330): the
        # raw `session_id` is byte-identical to the `onetime.session` cookie and
        # `key` embeds it, so both are INTERNAL. {List} strips them unless the
        # caller explicitly opts in (only `bin/ots session` does), and no HTTP
        # response may carry them.
        #
        # @param session_id [String]
        # @param key [String]
        # @param data [Hash] parsed session data
        # @return [Hash]
        def summarize(session_id, key, data)
          {
            session_handle: Onetime::SessionMetadata.handle_for(session_id),
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
        # identity fields, plus the session handle when the caller supplies the
        # sid it was derived from.
        #
        # The console shows operators handles and nothing else (#4330), so a
        # search box that could not match one would be a regression with no
        # operator workaround. Handles match on PREFIX because the table renders
        # a truncated handle — what the operator can copy is the first N chars.
        #
        # @param data [Hash]
        # @param term [String]
        # @param session_id [String, nil] keyword-optional so the CLI adapter,
        #   which searches raw rows, keeps working unchanged.
        # @return [Boolean]
        def matches_search?(data, term, session_id: nil)
          needle = term.to_s.downcase
          return false if needle.empty?

          if session_id && needle.match?(HANDLE_SEARCH_PATTERN)
            handle = Onetime::SessionMetadata.handle_for(session_id)
            return true if handle&.start_with?(needle)
          end

          [
            data['email'],
            data['external_id'],
            data['account_external_id'],
          ].compact.any? { |field| field.downcase.include?(needle) }
        end

        # Resolve an opaque session handle back to its raw session id.
        #
        # Non-reversible by construction (the handle is a truncated HMAC keyed on
        # OT.global_secret), so this recomputes handles and compares.
        #
        # TWO STAGES, cheap first:
        #   1. owner hint — when the caller knows which account owns the session
        #      (the console listing carries external_id on every row), walk only
        #      that customer's active_sessions ZSET. Single-digit cost, the same
        #      path RevokeCustomerSession takes.
        #   2. bounded keyspace SCAN — at most {MAX_SCAN} keys, CONTRACT 6 (never
        #      a blocking KEYS). Covers untracked/legacy blobs and hint misses.
        #
        # @param dbclient [Object]
        # @param session_handle [String] 32-char lowercase hex
        # @param owner_hint [String, nil] extid/email/objid of the presumed owner
        # @return [Array(String, Boolean), Array(nil, Boolean)] `[sid, scan_capped]`.
        #   scan_capped is true when stage 2 ran AND hit {MAX_SCAN}, i.e. a nil sid
        #   may mean "not sampled" rather than "does not exist". Callers MUST
        #   surface it — which is why this returns a pair and not a bare sid.
        def resolve_handle(dbclient, session_handle, owner_hint: nil)
          handle = session_handle.to_s.downcase
          return [nil, false] unless handle.match?(HANDLE_PATTERN)

          if (sid = resolve_handle_via_owner(owner_hint, handle))
            return [sid, false]
          end

          keys   = scan_keys(dbclient)
          capped = keys.size >= MAX_SCAN
          keys.each do |key|
            sid = extract_id(key)
            return [sid, capped] if Onetime::SessionMetadata.handle_for(sid) == handle
          end
          [nil, capped]
        end

        # Stage 1 of {resolve_handle}: match the handle over one customer's own
        # bounded active_sessions set. The hint is NOT authorization — it only
        # picks a cheaper search space, and a wrong hint simply misses.
        #
        # @param owner_hint [String, nil]
        # @param handle [String] downcased 32-hex handle
        # @return [String, nil]
        def resolve_handle_via_owner(owner_hint, handle)
          return nil if owner_hint.to_s.empty?

          customer = Onetime::Customer.load_by_extid_or_email(owner_hint) ||
                     Onetime::Customer.load(owner_hint)
          return nil unless customer&.exists?

          customer.active_sessions.revrange(0, -1).find do |sid|
            Onetime::SessionMetadata.handle_for(sid) == handle
          end
        rescue StandardError => ex
          OT.ld "[Sessions::Store] owner-hinted handle resolution failed: #{ex.message}"
          nil
        end
      end
    end
  end
end

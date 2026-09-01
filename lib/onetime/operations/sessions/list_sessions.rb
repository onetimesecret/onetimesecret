# lib/onetime/operations/sessions/list_sessions.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'
require 'onetime/models/session_metadata'

module Onetime
  module Operations
    module Sessions
      # List active sessions — the SINGLE implementation of the session-list verb
      # (epic #40 / D3). The colonel endpoint (`GET /api/colonel/sessions`) and the
      # `bin/ots session list` / `search` CLI commands are thin adapters over it.
      #
      # READ-ONLY: inspecting sessions mutates nothing, so — like the billing
      # catalog / system read-outs — it records NO {Onetime::ColonelAuditEvent}
      # (CONTRACT 4: audit is for mutations).
      #
      # Bounded by construction (CONTRACT 6): the listing is a bounded cursor SCAN
      # (never a blocking KEYS), collected once and paginated in memory. Results are
      # sorted newest-authenticated first (nils last), tiebroken by session id, so
      # pagination is stable across pages.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class List
        # @!attribute sessions [r] Array<Hash> one page of {Store.summarize} rows,
        #   each decorated with `:geo_country` from the metadata sidecar
        #   (see {#attach_geo_country}); nil when no sidecar record survives.
        #   Rows identify a session by `:session_handle`; the internal
        #   `:session_id` / `:key` are present ONLY when the caller passed
        #   `reveal_session_id: true` (#4330)
        # @!attribute total_count [r] Integer identity sessions matched (pre-pagination)
        # @!attribute scanned [r] Integer session keys examined this scan
        # @!attribute anonymous_count [r] Integer scanned keys with no actor identity (filtered out)
        # @!attribute scan_capped [r] Boolean the bounded scan hit {Store::MAX_SCAN}
        #   (identity sessions beyond the window are NOT listed — counts would
        #   otherwise silently understate; the by-id inspect path is unaffected)
        Result = Data.define(
          :sessions,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :scanned,
          :anonymous_count,
          :scan_capped,
        )

        # Cap on page size, matching the colonel list convention (list_secrets.rb).
        MAX_PER_PAGE     = 100
        DEFAULT_PER_PAGE = 50

        # @param page [Integer] 1-based page (clamped to >= 1).
        # @param per_page [Integer] page size (clamped to 1..MAX_PER_PAGE).
        # @param search [String, nil] optional free-text identity filter (identity
        #   fields, or a session-handle prefix).
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        # @param reveal_session_id [Boolean] include the INTERNAL `:session_id` and
        #   `:key` on each row. Defaults FALSE — fail-closed (#4330): the raw sid is
        #   byte-identical to the `onetime.session` cookie, so only the local
        #   `bin/ots session` CLI — whose whole purpose is to hand the operator an
        #   id for `inspect`/`delete` — opts in. Every HTTP consumer gets
        #   `session_handle` only.
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE, search: nil, dbclient: nil,
                       reveal_session_id: false)
          @page              = page.to_i < 1 ? 1 : page.to_i
          @per_page          = clamp_per_page(per_page)
          @search            = search.to_s.empty? ? nil : search.to_s
          @dbclient          = dbclient
          @reveal_session_id = reveal_session_id
        end

        # @return [Result]
        def call
          db    = @dbclient || Familia.dbclient
          codec = Onetime::SessionCodec.from_config
          keys  = Store.scan_keys(db)
          rows  = collect(db, keys, codec)

          # Anonymous sessions (CSRF-token-only visitors) dominate the keyspace
          # and carry nothing investigable — no actor, no IP, no user agent — so
          # they are excluded from the incident-response listing. They are still
          # counted so the operator sees the true keyspace shape rather than a
          # list that looks empty for no reason.
          identified, anonymous = rows.partition { |row| Store.identified?(row[:__data]) }
          if @search
            identified.select! do |row|
              Store.matches_search?(row[:__data], @search, session_id: row[:session_id])
            end
          end
          identified.sort_by! { |row| [-(row[:created_at] || 0), row[:session_id].to_s] }
          identified.each { |row| row.delete(:__data) }

          total_count = identified.size
          total_pages = @per_page.zero? ? 0 : (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page
          # The geo join keys on :session_id, so the internal identifiers are
          # stripped only after it — and only when the caller did not opt in.
          page_rows   = attach_geo_country(identified[start_idx, @per_page] || [])
          page_rows   = strip_internal_identifiers(page_rows) unless @reveal_session_id

          Result.new(
            sessions: page_rows,
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
            scanned: keys.size,
            anonymous_count: anonymous.size,
            scan_capped: keys.size >= Store::MAX_SCAN,
          )
        end

        private

        # Drop the bearer-shaped identifiers from the rows that leave this op
        # (#4330). `:session_id` IS the `onetime.session` cookie value and `:key`
        # embeds it; `:session_handle` — a non-reversible keyed digest — is the
        # identifier every consumer routes on instead.
        def strip_internal_identifiers(rows)
          rows.each do |row|
            row.delete(:session_id)
            row.delete(:key)
          end
        end

        # Bounded scan → decode → summarize. The parsed session data rides along
        # under `:__data` so the identity partition and the search predicate can
        # run before it is stripped for output. The shared codec decrypts each
        # value (see {Store#load_data}); without it every row would be the opaque
        # `_raw` fallback and nothing would classify as identified.
        def collect(db, keys, codec)
          keys.filter_map do |key|
            data = Store.load_data(db, key, codec: codec)
            next nil unless data

            Store.summarize(Store.extract_id(key), key, data).merge(__data: data)
          end
        end

        # Decorate one page of rows with the country recorded on each session's
        # metadata sidecar.
        #
        # Country lives ONLY on the sidecar: Otto resolves it per request into
        # `env['otto.privacy.geo_country']` and TrackMetadata stamps it onto
        # {Onetime::SessionMetadata}. It is never written into the encrypted
        # session blob this listing decrypts, so the global console has to join
        # to get it — there is nothing to read out of `data`.
        #
        # Deliberately applied AFTER pagination, and so NOT folded into
        # {Store.summarize}: summarize runs once per scanned key (up to
        # {Store::MAX_SCAN}), while this runs once per row actually returned —
        # a single pipelined {Familia::Horreum.load_multi} round trip for the
        # page (at most {MAX_PER_PAGE} HGETALLs in ONE pipeline) instead of up
        # to ten thousand serial reads.
        #
        # Absence is normal and is not pruned. Unlike ListForCustomer — whose
        # source of truth IS the sidecar index, so a missing sidecar means a
        # stale member worth removing — here the session blob is the source of
        # truth and the sidecar is decoration. A session predating the sidecar,
        # or one whose 30d sidecar TTL lapsed, is still a live session; it just
        # has no country. A sidecar read must never take down the listing, for
        # the same reason {Store.load_data} swallows a bad key.
        #
        # geo_country is nil or a country code, NEVER Otto's '**' sentinel —
        # normalization lives on the {Onetime::SessionMetadata#geo_country}
        # reader itself (the single chokepoint), not here.
        def attach_geo_country(rows)
          metas = load_sidecars(rows.map { |row| row[:session_id] })
          rows.each_with_index do |row, idx|
            row[:geo_country] = metas[idx]&.geo_country
          end
        end

        # One pipelined round trip for the whole page. load_multi is
        # position-aligned with its input (nil for missing/blank sids), which is
        # exactly the old per-row nil-tolerance. Because the batch materializes
        # every record in one call, ANY failure inside it (connection error, or
        # one corrupt record raising during instantiation) would otherwise cost
        # the whole page its decoration — so it degrades to the legacy per-row
        # loads, where each failure degrades only its own row to no-country.
        def load_sidecars(session_ids)
          return [] if session_ids.empty?

          Onetime::SessionMetadata.load_multi(session_ids)
        rescue StandardError => ex
          OT.le "[session-list] batched sidecar geo lookup failed: #{ex.class}: #{ex.message}"
          session_ids.map do |sid|
            Onetime::SessionMetadata.load(sid)
          rescue StandardError => row_ex
            OT.le "[session-list] sidecar geo lookup failed: #{row_ex.class}: #{row_ex.message}"
            nil
          end
        end

        def clamp_per_page(value)
          n = value.to_i
          return DEFAULT_PER_PAGE if n <= 0
          return MAX_PER_PAGE if n > MAX_PER_PAGE

          n
        end
      end
    end
  end
end

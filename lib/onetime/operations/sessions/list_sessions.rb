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
        #   (see {#attach_geo_country}); nil when no sidecar record survives
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
        # @param search [String, nil] optional free-text identity filter.
        # @param dbclient [Object, nil] Redis-like client; defaults to Familia.dbclient.
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE, search: nil, dbclient: nil)
          @page     = page.to_i < 1 ? 1 : page.to_i
          @per_page = clamp_per_page(per_page)
          @search   = search.to_s.empty? ? nil : search.to_s
          @dbclient = dbclient
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
          identified.select! { |row| Store.matches_search?(row[:__data], @search) } if @search
          identified.sort_by! { |row| [-(row[:created_at] || 0), row[:session_id].to_s] }
          identified.each { |row| row.delete(:__data) }

          total_count = identified.size
          total_pages = @per_page.zero? ? 0 : (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page
          page_rows   = attach_geo_country(identified[start_idx, @per_page] || [])

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
        # at most {MAX_PER_PAGE} HGETs instead of up to ten thousand.
        #
        # Absence is normal and is not pruned. Unlike ListForCustomer — whose
        # source of truth IS the sidecar index, so a missing sidecar means a
        # stale member worth removing — here the session blob is the source of
        # truth and the sidecar is decoration. A session predating the sidecar,
        # or one whose 30d sidecar TTL lapsed, is still a live session; it just
        # has no country. A sidecar read must never take down the listing, for
        # the same reason {Store.load_data} swallows a bad key.
        def attach_geo_country(rows)
          rows.each do |row|
            row[:geo_country] = begin
              Onetime::SessionMetadata.load(row[:session_id])&.geo_country
            rescue StandardError => ex
              OT.le "[session-list] sidecar geo lookup failed: #{ex.class}: #{ex.message}"
              nil
            end
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

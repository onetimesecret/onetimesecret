# lib/onetime/operations/sessions/list_sessions.rb
#
# frozen_string_literal: true

require 'onetime/operations/sessions/store'

module Onetime
  module Operations
    module Sessions
      # List active sessions — the SINGLE implementation of the session-list verb
      # (epic #40 / D3). The colonel endpoint (`GET /api/colonel/sessions`) and the
      # `bin/ots session list` / `search` CLI commands are thin adapters over it.
      #
      # READ-ONLY: inspecting sessions mutates nothing, so — like the billing
      # catalog / system read-outs — it records NO {Onetime::AdminAuditEvent}
      # (CONTRACT 4: audit is for mutations).
      #
      # Bounded by construction (CONTRACT 6): the listing is a bounded cursor SCAN
      # (never a blocking KEYS), collected once and paginated in memory. Results are
      # sorted newest-authenticated first (nils last), tiebroken by session id, so
      # pagination is stable across pages.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class List
        # @!attribute sessions [r] Array<Hash> one page of {Store.summarize} rows
        # @!attribute total_count [r] Integer sessions matched (pre-pagination)
        Result = Data.define(:sessions, :total_count, :page, :per_page, :total_pages)

        # Cap on page size, matching the colonel list convention (list_secrets.rb).
        MAX_PER_PAGE = 100
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
          db   = @dbclient || Familia.dbclient
          rows = collect(db)

          rows.select! { |row| Store.matches_search?(row[:__data], @search) } if @search
          rows.sort_by! { |row| [-(row[:created_at] || 0), row[:session_id].to_s] }
          rows.each { |row| row.delete(:__data) }

          total_count = rows.size
          total_pages = @per_page.zero? ? 0 : (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page
          page_rows   = rows[start_idx, @per_page] || []

          Result.new(
            sessions: page_rows,
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
          )
        end

        private

        # Bounded scan → load → summarize. The parsed session data rides along under
        # `:__data` so the search predicate can run before it is stripped for output.
        def collect(db)
          Store.scan_keys(db).filter_map do |key|
            data = Store.load_data(db, key)
            next nil unless data

            Store.summarize(Store.extract_id(key), key, data).merge(__data: data)
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

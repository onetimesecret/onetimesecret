# lib/onetime/operations/domains/orphaned_scan.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) diagnostic operation — see decision D3 in
# lib/onetime/operations/README.md. Lives alongside the incumbent domain ops in
# lib/onetime/operations, under the Domains:: namespace.

module Onetime
  module Operations
    module Domains
      # Scan for orphaned custom domains — the SINGLE implementation of the
      # orphaned-scan verb (epic #43 / D3). An orphaned domain is one with no
      # owning organization (`org_id` blank), a data-integrity smell the operator
      # can then repair.
      #
      # READ-ONLY: records NO {Onetime::AdminAuditEvent} (CONTRACT 4). The
      # `bin/ots domains orphaned` CLI and the colonel endpoint
      # (`GET /api/colonel/domains/orphaned`) are thin adapters over it.
      #
      # Bounded by construction (CONTRACT 6): iteration is over the
      # `CustomDomain.instances` sorted set (a bounded members list, NOT a blocking
      # KEYS scan) — the same source the existing colonel domains list uses — via
      # `instances.all` + per-identifier `find_by_identifier` (mirroring the CLI's
      # bulk-repair/orphaned iteration). Results are sorted by display_domain (parity
      # with the CLI) and paginated in memory.
      #
      # ## CLI parity
      #
      # `bin/ots domains orphaned` lists ALL orphaned domains sorted by
      # display_domain. Passing `per_page: nil` (the CLI adapter's call) returns the
      # full sorted collection unpaginated, preserving that output; the colonel
      # endpoint passes real page/per_page for a paginated list.
      class OrphanedScan
        # @!attribute domains [r] Array<Hash> one page of orphaned-domain summaries
        Result = Data.define(:domains, :total_count, :page, :per_page, :total_pages)

        MAX_PER_PAGE     = 100
        DEFAULT_PER_PAGE = 50

        # @param page [Integer] 1-based page (clamped to >= 1). Ignored when unpaginated.
        # @param per_page [Integer, nil] page size; nil returns the full list (CLI mode).
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE)
          @page       = page.to_i < 1 ? 1 : page.to_i
          @unpaginated = per_page.nil?
          @per_page   = @unpaginated ? nil : clamp_per_page(per_page)
        end

        # @return [Result]
        def call
          orphaned = collect_orphaned.sort_by { |row| row[:display_domain].to_s }

          total_count = orphaned.size

          if @unpaginated
            return Result.new(
              domains: orphaned,
              total_count: total_count,
              page: 1,
              per_page: total_count,
              total_pages: 1,
            )
          end

          total_pages = @per_page.zero? ? 0 : (total_count.to_f / @per_page).ceil
          start_idx   = (@page - 1) * @per_page
          page_rows   = orphaned[start_idx, @per_page] || []

          Result.new(
            domains: page_rows,
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
          )
        end

        private

        # Bounded: instances.all returns the sorted set's member identifiers (a
        # ZRANGE over a bounded set, NOT a blocking KEYS scan). find_by_identifier
        # resolves each record; nil results (stale identifiers whose records are
        # gone) are dropped by filter_map.
        def collect_orphaned
          all_ids = Onetime::CustomDomain.instances.all

          all_ids.filter_map do |identifier|
            domain = Onetime::CustomDomain.find_by_identifier(identifier)
            next nil unless domain
            next nil unless domain.org_id.to_s.empty?

            summarize(domain)
          end
        end

        def summarize(domain)
          {
            domain_id: domain.domainid,
            extid: (domain.extid if domain.respond_to?(:extid)),
            display_domain: domain.display_domain,
            verification_state: domain.verification_state.to_s,
            verified: domain.verified.to_s == 'true',
            created: domain.created,
          }
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

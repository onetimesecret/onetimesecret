# lib/onetime/operations/domains/list.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) diagnostic operation — the SINGLE implementation of
# the domains-list verb. Extracted verbatim from the colonel
# ColonelAPI::Logic::Colonel::ListCustomDomains so the admin API endpoint
# (GET /api/colonel/domains) and `bin/ots domains list` read domains the same
# bounded, index-backed way instead of each carrying its own load pattern.
#
# READ-ONLY: records NO {Onetime::ColonelAuditEvent} (CONTRACT 4). The colonel
# Logic class is now a thin adapter that sanitizes HTTP params, checks the
# colonel role, calls this op, and shapes the response envelope — its wire shape
# is unchanged. The CLI is a second thin adapter.
#
# ## Index-backed reads, never load-all (epic #20 / #2211)
#
# Each PAGINATED path reads only a bounded set (this is the load pattern that
# used to pin the web workers on every debounced admin keystroke):
#
# - UNFILTERED: one ZREVRANGE page off `CustomDomain.instances` (scored by SAVE
#   time, so most-recently-modified-first) + a load_multi of just that page.
#   total_count is the set cardinality (ZCARD).
# - SEARCH: a bounded cursor HSCAN over `display_domain_index` with a server-side
#   `*term*` glob, merged with exact extid / domain_id lookups. Doubly bounded by
#   SEARCH_MATCH_LIMIT and SEARCH_SCAN_ROUNDS.
# - ORG FILTER (without search): the org's `domains` participation set UNIONED
#   with a bounded HSCAN of the `owners` class hashkey (recovers domains whose
#   participation-set membership drifted from their authoritative org_id).
# - STATUS FILTER alone: the newest STATUS_SCAN_LIMIT domains, filtered in Ruby,
#   with `capped` set when the population exceeds the window.
#
# ## CLI mode (per_page: nil)
#
# `per_page: nil` returns the FULL population unpaginated (mirrors
# OrphanedScan's CLI adapter). This is a deliberate load-all — the CLI's
# duplicate-record diagnostic groups by display_domain across the whole set, so
# it cannot page — and matches the incumbent `bin/ots domains list` behaviour.
# The colonel endpoint always passes a real per_page and never takes this path.

module Onetime
  module Operations
    module Domains
      class List
        # Per-round-trip COUNT hint for the display_domain_index cursor HSCAN.
        SCAN_COUNT = 100

        # Cap on how many display_domain_index MATCHES one search collects.
        SEARCH_MATCH_LIMIT = 1_000

        # Cap on HSCAN round-trips for one search.
        SEARCH_SCAN_ROUNDS = 1_000

        # Request-path cap on the newest-first window a status-only filter reads.
        STATUS_SCAN_LIMIT = 5_000

        # @!attribute domains [r] Array<Hash> one page (or the full set, in CLI
        #   mode) of wire-shaped domain rows — identical to the colonel response.
        Result = Data.define(:domains, :total_count, :page, :per_page, :total_pages, :capped)

        # @param page [Integer] 1-based page (clamped to >= 1). Ignored when unpaginated.
        # @param per_page [Integer, nil] page size (clamped to 1..100); nil returns
        #   the full population unpaginated (CLI mode).
        # @param search [String] case-insensitive display_domain substring, or an
        #   exact extid / domain_id.
        # @param status [String] exact verification_state ('verified', 'pending', ...).
        # @param org_id [String] owning-org extid or objid.
        def initialize(page: 1, per_page: 50, search: '', status: '', org_id: '')
          @unpaginated   = per_page.nil?
          @page          = page.to_i < 1 ? 1 : page.to_i
          @per_page      = @unpaginated ? nil : clamp_per_page(per_page)
          @search_term   = search.to_s.strip
          @status_filter = status.to_s
          @org_filter    = org_id.to_s
          @capped        = false
        end

        # @return [Result]
        def call
          @unpaginated ? call_unpaginated : call_paginated
        end

        private

        def clamp_per_page(value)
          n = value.to_i
          n = 50 if n < 1
          n = 100 if n > 100
          n
        end

        def call_paginated
          if active_filters?
            matches     = apply_residual_filters(filtered_candidates)
            total_count = matches.size

            # Preserve the incumbent within-page ordering for filtered reads
            # (created descending).
            matches.sort_by! { |domain| -(domain.created || 0).to_f }

            start_idx         = (@page - 1) * @per_page
            paginated_domains = matches[start_idx, @per_page] || []
          else
            # Default admin view: page straight off the instances sorted set.
            total_count       = Onetime::CustomDomain.instances.count
            start_idx         = (@page - 1) * @per_page
            end_idx           = start_idx + @per_page - 1
            page_ids          = Onetime::CustomDomain.instances.revrange(start_idx, end_idx)
            paginated_domains = Onetime::CustomDomain.load_multi(page_ids).compact
          end

          total_pages = (total_count.to_f / @per_page).ceil

          Result.new(
            domains: build_domain_rows(paginated_domains),
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
            capped: @capped,
          )
        end

        # CLI mode: the full population (filtered candidates when filters are
        # active, else every instance), unpaginated. Sorted created-descending
        # for a stable order the CLI can re-sort on top of.
        def call_unpaginated
          candidates =
            if active_filters?
              apply_residual_filters(filtered_candidates)
            else
              all_ids = Onetime::CustomDomain.instances.revrange(0, -1)
              Onetime::CustomDomain.load_multi(all_ids).compact
            end

          candidates.sort_by! { |domain| -(domain.created || 0).to_f }
          total_count = candidates.size

          Result.new(
            domains: build_domain_rows(candidates),
            total_count: total_count,
            page: 1,
            per_page: total_count,
            total_pages: 1,
            capped: @capped,
          )
        end

        def active_filters?
          !@search_term.empty? || !@status_filter.empty? || !@org_filter.empty?
        end

        # The bounded candidate set for a filtered request, from the narrowest
        # available index: search beats the org read beats the status window.
        def filtered_candidates
          return search_candidates unless @search_term.empty?
          return org_candidates unless @org_filter.empty?

          status_window_candidates
        end

        def search_candidates
          objids, scan_capped = scan_display_domain_index(@search_term)
          @capped           ||= scan_capped

          matches = Onetime::CustomDomain.load_multi(objids).compact
          merge_identifier_matches(matches)
          matches
        end

        # Non-blocking cursor HSCAN of the display_domain_index hash, matching
        # `*term*` server-side against the lowercased stored domains.
        def scan_display_domain_index(term)
          dbkey    = Onetime::CustomDomain.display_domain_index.dbkey
          dbclient = Onetime::CustomDomain.dbclient
          pattern  = "*#{glob_escape(term.downcase)}*"
          objids   = []
          cursor   = '0'
          rounds   = 0

          loop do
            cursor, entries = dbclient.hscan(dbkey, cursor, match: pattern, count: SCAN_COUNT)
            entries.each { |_display_domain, objid| objids << objid }
            rounds         += 1

            break if cursor == '0'
            break if objids.size >= SEARCH_MATCH_LIMIT
            break if rounds >= SEARCH_SCAN_ROUNDS
          end

          capped = cursor != '0' || objids.size > SEARCH_MATCH_LIMIT
          [objids.first(SEARCH_MATCH_LIMIT), capped]
        end

        def merge_identifier_matches(matches)
          seen = matches.map(&:identifier)

          identifier_lookups(@search_term).each do |domain|
            next if seen.include?(domain.identifier)

            matches << domain
            seen << domain.identifier
          end
        end

        def identifier_lookups(term)
          [
            safe_lookup { Onetime::CustomDomain.find_by_extid(term) },
            safe_lookup { Onetime::CustomDomain.load(term) },
          ].compact.select(&:exists?)
        end

        def safe_lookup
          yield
        rescue StandardError
          nil
        end

        def glob_escape(term)
          term.gsub(/[*?\[\]\\]/) { |char| "\\#{char}" }
        end

        # The org's own domains participation set unioned with the org's entries
        # in the `owners` class hashkey. Accepts the org extid or the objid.
        def org_candidates
          org = resolve_org(@org_filter)
          return [] unless org&.exists?

          candidates = org.list_domains
          merge_unlisted_owned(candidates, org)
          candidates
        end

        def merge_unlisted_owned(candidates, org)
          seen                    = candidates.map(&:identifier)
          owned_ids, scan_capped  = scan_owners_index(org.objid)
          @capped               ||= scan_capped

          Onetime::CustomDomain.load_multi(owned_ids - seen).compact.each do |domain|
            candidates << domain
          end
        end

        # Walk the owners hash (domainid -> org objid) collecting this org's
        # domainids. Values on the wire are JSON-serialized, so match both the
        # JSON and raw form.
        def scan_owners_index(org_objid)
          dbkey    = Onetime::CustomDomain.owners.dbkey
          dbclient = Onetime::CustomDomain.dbclient
          wanted   = [org_objid, org_objid.to_json]
          owned    = []
          cursor   = '0'
          rounds   = 0

          loop do
            cursor, entries = dbclient.hscan(dbkey, cursor, count: SCAN_COUNT)
            entries.each { |domain_id, owner| owned << domain_id if wanted.include?(owner) }
            rounds         += 1

            break if cursor == '0'
            break if owned.size >= SEARCH_MATCH_LIMIT
            break if rounds >= SEARCH_SCAN_ROUNDS
          end

          capped = cursor != '0' || owned.size > SEARCH_MATCH_LIMIT
          [owned.first(SEARCH_MATCH_LIMIT), capped]
        end

        def resolve_org(identifier)
          safe_lookup { Onetime::Organization.find_by_extid(identifier) } ||
            safe_lookup { Onetime::Organization.load(identifier) }
        end

        def status_window_candidates
          window_ids = Onetime::CustomDomain.instances.revrange(0, STATUS_SCAN_LIMIT - 1)
          @capped  ||= Onetime::CustomDomain.instances.count > window_ids.size

          Onetime::CustomDomain.load_multi(window_ids).compact
        end

        def apply_residual_filters(result)
          unless @status_filter.empty?
            result = result.select { |d| d.verification_state.to_s == @status_filter }
          end

          unless @org_filter.empty?
            org_ids = [@org_filter, resolve_org(@org_filter)&.objid].compact.map(&:to_s)
            result  = result.select { |d| org_ids.include?(d.org_id.to_s) }
          end

          return result if @search_term.empty?

          needle = @search_term.downcase
          result.select do |d|
            next true if d.extid.to_s == @search_term
            next true if d.domainid.to_s == @search_term

            d.display_domain.to_s.downcase.include?(needle) ||
              d.base_domain.to_s.downcase.include?(needle)
          end
        end

        # Format the page of domains for the wire — identical shape to the
        # colonel response the CLI/API both consume.
        def build_domain_rows(paginated_domains)
          domain_identifiers = paginated_domains.map(&:identifier)
          homepage_by_id     = Onetime::CustomDomain::HomepageConfig
            .load_multi(domain_identifiers).compact
            .to_h { |cfg| [cfg.domain_id, cfg] }
          api_by_id          = Onetime::CustomDomain::ApiConfig
            .load_multi(domain_identifiers).compact
            .to_h { |cfg| [cfg.domain_id, cfg] }

          paginated_domains.map do |domain|
            org = domain.primary_organization

            brand_raw  = domain.brand.hgetall
            brand_data = {
              name: brand_raw['name'],
              tagline: brand_raw['tagline'],
              homepage_url: brand_raw['homepage_url'],
            }

            homepage_config = homepage_by_id[domain.identifier]
            api_config      = api_by_id[domain.identifier]

            has_logo = !domain.logo['filename'].to_s.empty?
            has_icon = !domain.icon['filename'].to_s.empty?

            {
              domain_id: domain.domainid,
              extid: domain.extid,
              display_domain: domain.display_domain,
              base_domain: domain.base_domain,
              subdomain: domain.subdomain,
              status: domain.status,
              verified: domain.verified.to_s == 'true',
              resolving: domain.resolving.to_s == 'true',
              verification_state: domain.verification_state.to_s,
              ready: domain.ready?,
              created: domain.created,
              updated: domain.updated,
              org_id: domain.org_id,
              org_name: org ? org.display_name : 'Unknown',
              brand: brand_data,
              homepage_config: homepage_config && {
                domain_id: homepage_config.domain_id,
                enabled: homepage_config.enabled?,
                secrets_mode: homepage_config.secrets_mode_value,
                created_at: homepage_config.created&.to_i,
                updated_at: homepage_config.updated&.to_i,
              },
              api_config: api_config && {
                domain_id: api_config.domain_id,
                enabled: api_config.enabled?,
                created_at: api_config.created&.to_i,
                updated_at: api_config.updated&.to_i,
              },
              has_logo: has_logo,
              has_icon: has_icon,
              logo_url: has_logo ? "/imagine/#{domain.domainid}/logo.png" : nil,
              icon_url: has_icon ? "/imagine/#{domain.domainid}/icon.png" : nil,
            }
          end
        end
      end
    end
  end
end

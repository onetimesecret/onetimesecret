# apps/api/colonel/logic/colonel/list_custom_domains.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/domains/list'

module ColonelAPI
  module Logic
    module Colonel
      # List Custom Domains (Colonel)
      #
      # @api Returns a paginated list of all custom domains across all
      #   organizations, including verification state, brand settings,
      #   logo/icon presence, and the owning organization. Requires
      #   colonel role.
      #
      # Optional server-side filters (all additive; omitting them returns the
      # unfiltered paginated roster):
      #
      #   search  — case-insensitive substring over display_domain (which
      #             contains base_domain as its suffix, so base_domain
      #             substrings match too), or an exact extid / domain_id match.
      #   status  — exact verification_state ('verified', 'pending', ...).
      #   org_id  — exact owning-org match; accepts the org extid or objid.
      #
      # ## Index-backed reads, never load-all (epic #20 / #2211)
      #
      # The previous implementation loaded EVERY CustomDomain (load_multi of the
      # whole instances set) on every request — including each debounced
      # keystroke of the admin search box — and filtered/sliced in Ruby. Each
      # path now reads only a bounded set:
      #
      # - UNFILTERED (the default admin view): one ZREVRANGE page straight off
      #   `CustomDomain.instances` + a load_multi of just that page. The set is
      #   scored by SAVE time (Familia's touch_instances! re-scores on every
      #   save, and the maintenance rebuild job re-adds with now), so the
      #   default order is most-recently-modified-first — a deliberate
      #   contract change from the previous created-descending sort, the same
      #   one the users list declares for Customer.instances. total_count is
      #   the set cardinality (ZCARD).
      # - SEARCH: a bounded cursor HSCAN over the `display_domain_index` hash
      #   (display_domain -> objid, domains stored lowercase) with a server-side
      #   `*term*` glob — the same scan-with-match mechanism the users list uses
      #   against its email index — merged with exact extid / domain_id lookups
      #   (O(1) unique-index gets). Doubly bounded: matches are capped at
      #   SEARCH_MATCH_LIMIT and the scan stops after SEARCH_SCAN_ROUNDS
      #   round-trips, so a no-match term can never walk an unbounded index on
      #   one request. The glob term is escaped, so user input cannot inject
      #   pattern syntax.
      # - ORG FILTER (without search): the org's own `domains` participation
      #   set (bounded by that org's domain count) UNIONED with an HSCAN of
      #   the `owners` class hashkey (domainid -> org_id) that walks the
      #   global index under the same match/round caps as the search scan.
      #   The participation set can drift from the authoritative org_id field
      #   (create!'s set-add is conditional on the org loading; `domains
      #   doctor` models the state as repairable), and the admin list is
      #   exactly the surface an operator would use to find such a domain, so
      #   it must not hide it. The union recovers only that class — an
      #   `owners` entry still pointing at a PREVIOUS owner is filtered back
      #   out by the org_id predicate; reconciling stale owners entries is
      #   doctor's job, not the request path's.
      # - STATUS FILTER alone: there is no per-status index, so this reads the
      #   newest STATUS_SCAN_LIMIT domains from the instances set and filters in
      #   Ruby. Beyond the cap the response sets `pagination.capped` so the UI
      #   can say the count understates the population (mirrors the users list's
      #   role-filter contract).
      #
      # Filters compose: search (or the org read, or the status window) produces
      # the bounded candidate set; the remaining filters apply in Ruby on those
      # already-loaded rows. Filters are applied BEFORE pagination, so
      # total_count reflects the filtered set.
      class ListCustomDomains < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'customDomains' }.freeze

        attr_reader :domains,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :search_term,
          :status_filter,
          :org_filter,
          :capped

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @per_page = 100 if @per_page > 100 # Max 100 per page
          # A non-positive per_page would turn the unfiltered ZREVRANGE window
          # into revrange(0, -1) — the whole set, the exact load-all this
          # class exists to prevent — and then divide by zero computing
          # total_pages. Same lower clamp as Auth::Operations::Customers::List.
          @per_page = 50 if @per_page < 1
          @page     = 1 if @page < 1

          @search_term   = sanitize_plain_text(params['search'], max_length: 255).to_s.strip
          @status_filter = sanitize_identifier(params['status']).to_s
          @org_filter    = sanitize_identifier(params['org_id']).to_s
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        # Thin adapter: the bounded, index-backed listing computation now lives
        # in the single toolbox op {Onetime::Operations::Domains::List}, which
        # the `bin/ots domains list` CLI shares. This class keeps only the HTTP
        # concerns — param sanitization (#process_params), the colonel role
        # gate (#raise_concerns) and the response envelope (#success_data). The
        # wire shape is unchanged: the op returns the identical row hashes and
        # pagination scalars this method used to build inline.
        def process
          result = Onetime::Operations::Domains::List.new(
            page: @page,
            per_page: @per_page,
            search: @search_term,
            status: @status_filter,
            org_id: @org_filter,
          ).call

          @domains     = result.domains
          @total_count = result.total_count
          @page        = result.page
          @per_page    = result.per_page
          @total_pages = result.total_pages
          @capped      = result.capped

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              domains: domains,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                # true when a bounded scan/window stopped early, so total_count
                # understates the population (mirrors the users list contract).
                capped: capped,
              },
              # Server echo of the applied filters (additive key; mirrors
              # ListOrganizations). Never read for state by the frontend.
              filters: {
                search: search_term,
                status: status_filter,
                org_id: org_filter,
              },
            },
          }
        end
      end
    end
  end
end

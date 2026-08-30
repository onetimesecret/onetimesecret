# apps/api/colonel/logic/colonel/list_custom_domains.rb
#
# frozen_string_literal: true

require_relative '../base'

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
      #   scored at creation time (create!/import are the only writers), so the
      #   most-recent-first order matches the previous created-descending sort.
      #   total_count is the set cardinality (ZCARD).
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
      #   set — bounded by that org's domain count, never the global population.
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

        # Per-round-trip COUNT hint for the display_domain_index cursor HSCAN
        # (mirrors Auth::Operations::Customers::List::SCAN_COUNT).
        SCAN_COUNT = 100

        # Cap on how many display_domain_index MATCHES one search collects. A
        # page is at most 100 rows, so 1k matches is already 10 pages — anything
        # broader is a filter problem, not a pagination problem.
        SEARCH_MATCH_LIMIT = 1_000

        # Cap on HSCAN round-trips for one search. With SCAN_COUNT=100 this
        # bounds the index walk at ~100k entries examined even when the term
        # matches nothing (HSCAN MATCH filters server-side, so a no-match term
        # would otherwise walk the entire index).
        SEARCH_SCAN_ROUNDS = 1_000

        # Request-path cap on the newest-first window a status-only filter
        # reads from the instances set. Domains are a paid feature, so the
        # population sits far below this on every known deployment; if it ever
        # grows past the cap the filter degrades to a bounded window with
        # `pagination.capped` set, never an unbounded load.
        STATUS_SCAN_LIMIT = 5_000

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

        def process
          @capped = false

          if active_filters?
            matches = filtered_candidates
            matches = apply_residual_filters(matches)

            @total_count = matches.size

            # Preserve the incumbent within-page ordering for filtered reads
            # (created descending) — the candidate sources here (HSCAN, the
            # org's domains set, the status window) carry no single native
            # order worth exposing.
            matches.sort_by! { |domain| -(domain.created || 0).to_f }

            start_idx         = (@page - 1) * @per_page
            paginated_domains = matches[start_idx, @per_page] || []
          else
            # Default admin view: page straight off the instances sorted set,
            # loading only this page. total_count is the set cardinality
            # (ZCARD), so the envelope reflects the full population even
            # though only one page is ever loaded. Entries whose record was
            # deleted out from under the registry load as nil and are dropped
            # from the page (same graceful degradation as before).
            @total_count      = Onetime::CustomDomain.instances.count
            start_idx         = (@page - 1) * @per_page
            end_idx           = start_idx + @per_page - 1
            page_ids          = Onetime::CustomDomain.instances.revrange(start_idx, end_idx)
            paginated_domains = Onetime::CustomDomain.load_multi(page_ids).compact
          end

          @total_pages = (@total_count.to_f / @per_page).ceil
          @domains     = build_domain_rows(paginated_domains)

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

        private

        def active_filters?
          !search_term.empty? || !status_filter.empty? || !org_filter.empty?
        end

        # The bounded candidate set for a filtered request, from the narrowest
        # available index: search beats the org read beats the status window.
        # Whatever filters did not drive the read are applied afterwards in
        # Ruby by #apply_residual_filters — on candidates that are already
        # bounded, so that pass stays cheap.
        #
        # @return [Array<Onetime::CustomDomain>]
        def filtered_candidates
          return search_candidates unless search_term.empty?
          return org_candidates unless org_filter.empty?

          status_window_candidates
        end

        # Bounded HSCAN of display_domain_index plus exact identifier lookups,
        # deduped by identifier. Sets @capped when the scan stopped early.
        def search_candidates
          objids, scan_capped = scan_display_domain_index(search_term)
          @capped           ||= scan_capped

          matches = Onetime::CustomDomain.load_multi(objids).compact
          merge_identifier_matches(matches)
          matches
        end

        # Non-blocking cursor HSCAN of the display_domain_index hash
        # (display_domain -> objid), matching `*term*` server-side against the
        # lowercased stored domains. Doubly bounded — see the constants above.
        #
        # @return [Array(Array<String>, Boolean)] collected objids (capped at
        #   SEARCH_MATCH_LIMIT) and a capped flag — true when matches may have
        #   been dropped (the walk stopped before exhausting the index, or a
        #   completed walk overflowed the match cap).
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

        # Append exact extid / domain_id (objid) lookups for the search term,
        # skipping any domain the scan already found. Both are O(1)
        # unique-index gets — never a scan — so they cost nothing on a miss. A
        # malformed term is rescued to a miss rather than failing the search.
        def merge_identifier_matches(matches)
          seen = matches.map(&:identifier)

          identifier_lookups(search_term).each do |domain|
            next if seen.include?(domain.identifier)

            matches << domain
            seen << domain.identifier
          end
        end

        # @return [Array<Onetime::CustomDomain>]
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

        # Escape Redis glob metacharacters so a user-supplied term is always a
        # literal substring match, never pattern syntax.
        def glob_escape(term)
          term.gsub(/[*?\[\]\\]/) { |char| "\\#{char}" }
        end

        # The org's own domains participation set — bounded by that org's
        # domain count. Accepts the org extid (what every admin surface routes
        # by) or the internal objid, which is what CustomDomain#org_id stores.
        # An unknown org matches nothing, same as before.
        def org_candidates
          org = resolve_org(org_filter)
          return [] unless org&.exists?

          org.list_domains
        end

        # Extid-then-objid org resolution, shared by the candidate read and
        # the residual predicate so the two cannot drift. A malformed
        # identifier resolves to nil (a no-match filter), never an error.
        def resolve_org(identifier)
          safe_lookup { Onetime::Organization.find_by_extid(identifier) } ||
            safe_lookup { Onetime::Organization.load(identifier) }
        end

        # Status-only filter: newest STATUS_SCAN_LIMIT domains off the
        # instances set, filtered in Ruby by #apply_residual_filters. Sets
        # @capped when the population exceeds the window.
        def status_window_candidates
          window_ids = Onetime::CustomDomain.instances.revrange(0, STATUS_SCAN_LIMIT - 1)
          @capped  ||= Onetime::CustomDomain.instances.count > window_ids.size

          Onetime::CustomDomain.load_multi(window_ids).compact
        end

        # Apply every active filter to the already-bounded candidates. The
        # filter that drove the candidate read passes its own predicate
        # trivially (an HSCAN match still satisfies the search predicate, an
        # org-set member still satisfies the org predicate), so re-applying all
        # three keeps this a single composition point rather than tracking
        # which source skipped which filter.
        def apply_residual_filters(result)
          unless status_filter.empty?
            result = result.select { |d| d.verification_state.to_s == status_filter }
          end

          unless org_filter.empty?
            org_ids = [org_filter, resolve_org(org_filter)&.objid].compact.map(&:to_s)
            result  = result.select { |d| org_ids.include?(d.org_id.to_s) }
          end

          return result if search_term.empty?

          needle = search_term.downcase
          result.select do |d|
            next true if d.extid.to_s == search_term
            next true if d.domainid.to_s == search_term

            d.display_domain.to_s.downcase.include?(needle) ||
              d.base_domain.to_s.downcase.include?(needle)
          end
        end

        # Format the page of domains for the wire. Everything here is bounded
        # by the page size: the sibling HomepageConfig / ApiConfig records come
        # back in two pipelined load_multi fetches, and the org lookup runs
        # once per row.
        def build_domain_rows(paginated_domains)
          # HomepageConfig / ApiConfig use `identifier_field :domain_id`, so the
          # CustomDomain identifiers serve directly as load_multi keys. Missing
          # records come back as nil and are dropped by compact; lookup-misses
          # in the loop below become nil blocks in the JSON response.
          #
          # Consistent with CustomDomain's predicates (`#allow_public_homepage?`
          # / `#allow_public_api?`), which also fail-closed (return false +
          # log) when a sibling record is missing. Both read paths prefer
          # graceful degradation over raising so a single corrupt row can't
          # take down the admin list OR the user-facing authorization flow;
          # the write path (create! bootstrap, brand PUT upsert, migration)
          # is where integrity is enforced.
          domain_identifiers = paginated_domains.map(&:identifier)
          homepage_by_id     = Onetime::CustomDomain::HomepageConfig
            .load_multi(domain_identifiers).compact
            .to_h { |cfg| [cfg.domain_id, cfg] }
          api_by_id          = Onetime::CustomDomain::ApiConfig
            .load_multi(domain_identifiers).compact
            .to_h { |cfg| [cfg.domain_id, cfg] }

          paginated_domains.map do |domain|
            # Get organization details
            org = domain.primary_organization

            # Brand carries cosmetic fields only; the homepage / API toggles
            # live in their own per-domain records (#3026) and are emitted
            # alongside brand below.
            brand_raw  = domain.brand.hgetall
            brand_data = {
              name: brand_raw['name'],
              tagline: brand_raw['tagline'],
              homepage_url: brand_raw['homepage_url'],
            }

            homepage_config = homepage_by_id[domain.identifier]
            api_config      = api_by_id[domain.identifier]

            # Check if images exist
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

# apps/api/colonel/logic/colonel/list_organizations.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'

module ColonelAPI
  module Logic
    module Colonel
      # List Organizations (Colonel)
      #
      # @api Returns a paginated list of organizations with billing and sync
      #   health details. Supports filtering by subscription status and sync
      #   status (synced, potentially_stale, unknown) plus a `search` term.
      #   Requires colonel role.
      #
      # Sync health helps identify organizations with potentially stale planid
      # after plan changes made via Stripe Dashboard/CLI (bypassing webhook flow).
      #
      # ## Index-backed reads, never load-all (epic #20 / #2211)
      #
      # The previous implementation loaded EVERY organization (instances.to_a +
      # load_multi of the whole fleet, then an owner load and two ZCARDs PER
      # org) on every filtered or searched request, behind a 90 s cache that
      # refused to store any roster over 8 MB. On a production-sized fleet the
      # roster is far past that cap, so the cache never wrote and every search
      # keystroke replayed the full fleet walk. That is what pinned the web
      # workers for 30-60 s at a time. Each path now reads a bounded set:
      #
      # - UNFILTERED (the default admin view): one ZREVRANGE page off
      #   `Organization.instances` + a load_multi of just that page. The set is
      #   scored by save time, so the order is most-recently-modified-first.
      #   total_count is the set cardinality.
      # - SEARCH: the union of
      #     * exact objid / extid lookups (O(1)),
      #     * a bounded cursor HSCAN over `contact_email_index` with a
      #       server-side case-insensitive `*term*` glob (SEARCH_MATCH_LIMIT
      #       matches / SEARCH_SCAN_ROUNDS round-trips, same shape as the users
      #       and domains lists),
      #     * a bounded HSCAN over `Customer.email_index` for OWNER emails,
      #       resolving at most OWNER_MATCH_LIMIT matched customers to the orgs
      #       they own, and
      #     * the newest FILTER_WINDOW_LIMIT organizations off the instances
      #       set, matched in Ruby on display_name / billing_email (there is no
      #       index for either).
      # - STATUS / SYNC-STATUS only: the same newest-first window, filtered in
      #   Ruby (no per-status index exists).
      #
      # Whenever a scan or the window stops short of the population, the
      # response sets `pagination.capped` so the UI can say the count is a
      # floor (mirrors the users and domains lists). The residual filters
      # compose in Ruby on the bounded candidate set, BEFORE pagination, so
      # total_count reflects the filtered set. Row hydration (owner email, the
      # two counts, sync status) runs only for the returned page, with the
      # owners batch-loaded.
      #
      # There is no roster cache any more: the bounded reads are one pipelined
      # load each, and the cache's size cap meant it never engaged where it
      # mattered. `refresh` is still accepted for older clients and ignored.
      #
      # @see Billing::BillingService for sync status computation logic
      class ListOrganizations < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelOrganizations' }.freeze

        # Per-round-trip COUNT hint for the index cursor HSCANs. Large on
        # purpose: a search should cover the index in a few hundred
        # round-trips, not thousands.
        SCAN_COUNT = 1_000

        # Cap on how many index MATCHES one search collects per index.
        SEARCH_MATCH_LIMIT = 1_000

        # Cap on HSCAN round-trips per index for one search.
        SEARCH_SCAN_ROUNDS = 1_000

        # Cap on customers matched by owner-email search whose owned
        # organizations are resolved (each costs one participation read).
        OWNER_MATCH_LIMIT = 100

        # Request-path cap on the newest-first instances window that the
        # status / sync-status filters and the display_name / billing_email
        # search read (same size as the domains list's status window).
        FILTER_WINDOW_LIMIT = 5_000

        attr_reader :organizations,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :status_filter,
          :sync_status_filter,
          :search_term,
          :capped

        def process_params
          @page               = (params['page'] || 1).to_i
          @per_page           = (params['per_page'] || 50).to_i
          @per_page           = 100 if @per_page > 100 # Max 100 per page
          @per_page           = 50 if @per_page < 1
          @page               = 1 if @page < 1
          @status_filter      = sanitize_identifier(params['status']).to_s      # subscription_status
          @sync_status_filter = sanitize_identifier(params['sync_status']).to_s # synced, potentially_stale, unknown
          # objid/extid exact, or a display_name / contact / billing / owner
          # email substring.
          @search_term        = sanitize_plain_text(params['search'], max_length: 255).to_s.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @capped             = false
          @owner_match_orgids = {}

          if active_filters?
            matches      = apply_residual_filters(filtered_candidates)
            matches.sort_by! { |org| -(org.created || 0).to_i }
            @total_count = matches.size

            start_idx = (@page - 1) * @per_page
            page_orgs = matches[start_idx, @per_page] || []
          else
            @total_count = Onetime::Organization.instances.size
            page_orgs    = paged_roster
          end

          @organizations = build_org_rows(page_orgs)
          @total_pages   = (@total_count.to_f / @per_page).ceil

          success_data
        end

        private

        # Default admin view: one page straight off the instances sorted set.
        def paged_roster
          start_idx    = (@page - 1) * @per_page
          end_idx      = start_idx + @per_page - 1
          page_org_ids = Onetime::Organization.instances.revrange(start_idx, end_idx)
          load(page_org_ids)
        end

        def active_filters?
          !status_filter.empty? || !sync_status_filter.empty? || !search_term.empty?
        end

        # The bounded candidate set for a filtered request. Search adds the
        # index-backed lookups on top of the window every filtered read uses.
        # An exact objid / extid hit IS the answer: the two O(1) lookups settle
        # it without touching either index or the window.
        def filtered_candidates
          return window_candidates if search_term.empty?

          exact = identifier_lookups
          return exact unless exact.empty?

          candidates = {}
          [contact_email_candidates, owner_email_candidates, window_candidates].each do |found|
            found.each { |org| candidates[org.objid] ||= org }
          end
          candidates.values
        end

        # Newest FILTER_WINDOW_LIMIT organizations by save time. Sets `capped`
        # when the population is larger than the window.
        def window_candidates
          instances  = Onetime::Organization.instances
          window_ids = instances.revrange(0, FILTER_WINDOW_LIMIT - 1)
          @capped  ||= instances.size > window_ids.size
          load(window_ids)
        end

        # Exact objid / extid hits — O(1) unique-index reads. Both lookups
        # existence-check as they load (Familia `load`/`find_by_extid` run with
        # `check_exists: true` and return nil for a missing record), so
        # `.compact` alone yields only rows that exist. A second `exists?` here
        # would recheck on a possibly-different pooled connection and could
        # false-negative, dropping an organization the load just confirmed.
        def identifier_lookups
          [
            safe_lookup { Onetime::Organization.find_by_extid(search_term) },
            safe_lookup { Onetime::Organization.load(search_term) },
          ].compact
        end

        # Organizations whose contact_email contains the term. The index stores
        # addresses as entered, so the glob is built case-insensitively.
        def contact_email_candidates
          objids, scan_capped = scan_hash_index(
            Onetime::Organization.contact_email_index.dbkey,
            Onetime::Organization.dbclient,
            search_term,
          )
          @capped           ||= scan_capped
          load(objids)
        end

        # Organizations OWNED by a customer whose email contains the term.
        # Customer.email_index stores lowercased addresses. The matched
        # customers are capped at OWNER_MATCH_LIMIT because each one costs a
        # participation read to find its organizations; past the cap the
        # response is marked capped.
        def owner_email_candidates
          custids, scan_capped = scan_hash_index(
            Onetime::Customer.email_index.dbkey,
            Onetime::Customer.dbclient,
            search_term,
            limit: OWNER_MATCH_LIMIT,
          )
          @capped            ||= scan_capped

          customers = Onetime::Customer.load_multi(custids).compact
          customers.flat_map do |cust|
            owned = safe_lookup { cust.organization_instances.to_a } || []
            owned.select { |org| org.owner_id.to_s == cust.objid.to_s }
              .each { |org| @owner_match_orgids[org.objid] = true }
          end
        end

        # Non-blocking cursor HSCAN of a `field -> objid` index hash, matching
        # `*term*` server-side. Doubly bounded by `limit` matches and
        # SEARCH_SCAN_ROUNDS round-trips. Returns [objids, capped].
        def scan_hash_index(dbkey, dbclient, term, limit: SEARCH_MATCH_LIMIT)
          pattern = "*#{glob_case_insensitive(term)}*"
          objids  = []
          cursor  = '0'
          rounds  = 0

          loop do
            cursor, entries = dbclient.hscan(dbkey, cursor, match: pattern, count: SCAN_COUNT)
            entries.each { |_field, objid| objids << objid.to_s }
            rounds         += 1

            break if cursor == '0'
            break if objids.size >= limit
            break if rounds >= SEARCH_SCAN_ROUNDS
          end

          capped = cursor != '0' || objids.size > limit
          [objids.first(limit).uniq, capped]
        end

        # Escape glob metacharacters, then widen every letter to a `[aA]`
        # class so the server-side MATCH is case-insensitive.
        def glob_case_insensitive(term)
          term.each_char.map do |char|
            if char.match?(/[*?\[\]\\]/)
              "\\#{char}"
            elsif char.match?(/[a-zA-Z]/)
              "[#{char.downcase}#{char.upcase}]"
            else
              char
            end
          end.join
        end

        def safe_lookup
          yield
        rescue StandardError
          nil
        end

        def load(objids)
          return [] if objids.empty?

          Onetime::Organization.load_multi(objids).compact
        end

        def apply_residual_filters(orgs)
          result = orgs

          unless status_filter.empty?
            result = result.select { |org| org.subscription_status.to_s == status_filter }
          end

          unless sync_status_filter.empty?
            result = result.select { |org| compute_sync_status(org) == sync_status_filter }
          end

          return result if search_term.empty?

          result.select { |org| matches_search?(org) }
        end

        def matches_search?(org)
          return true if org.objid.to_s == search_term
          return true if org.extid.to_s == search_term
          return true if @owner_match_orgids.key?(org.objid)

          needle = search_term.downcase
          [org.display_name, org.contact_email, org.billing_email].any? do |value|
            value.to_s.downcase.include?(needle)
          end
        end

        # Hydrate the wire rows for ONE page. Owners are batch-loaded (one
        # pipeline), so the page costs a bounded number of reads regardless of
        # how the candidates were found.
        def build_org_rows(page_orgs)
          owner_ids = page_orgs.map { |org| org.owner_id.to_s }.reject(&:empty?).uniq
          owners    = owner_ids.empty? ? {} : Onetime::Customer.load_multi(owner_ids).compact.to_h { |c| [c.objid.to_s, c] }

          page_orgs.map { |org| build_org_data(org, owners[org.owner_id.to_s]) }
        end

        def build_org_data(org, owner)
          {
            org_id: org.objid,
            extid: org.extid,
            display_name: org.display_name,
            contact_email: org.contact_email,
            owner_id: org.owner_id,
            owner_email: owner&.email,
            member_count: org.member_count,
            domain_count: org.domain_count,
            is_default: org.is_default.to_s == 'true',
            created: org.created.to_i,
            updated: org.updated&.to_i,
            planid: org.planid,
            stripe_customer_id: org.stripe_customer_id,
            stripe_subscription_id: org.stripe_subscription_id,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end,
            billing_email: org.billing_email,
            sync_status: compute_sync_status(org),
            sync_status_reason: compute_sync_status_reason(org),
          }
        end

        def compute_sync_status(org)
          Billing::BillingService.compute_sync_status(org)
        end

        def compute_sync_status_reason(org)
          Billing::BillingService.compute_sync_status_reason(org)
        end

        def success_data
          {
            record: {},
            details: {
              organizations: organizations,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                # true when a bounded scan/window stopped early, so total_count
                # understates the population (mirrors the users list contract).
                capped: capped,
              },
              filters: {
                status: status_filter,
                sync_status: sync_status_filter,
                search: search_term,
              },
            },
          }
        end
      end
    end
  end
end

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
      # @api Returns a paginated list of all organizations with billing and
      #   sync health details. Supports filtering by subscription status and
      #   sync status (synced, potentially_stale, unknown). Requires colonel role.
      #
      # Sync health helps identify organizations with potentially stale planid
      # after plan changes made via Stripe Dashboard/CLI (bypassing webhook flow).
      #
      # @see Billing::BillingService for sync status computation logic
      #
      class ListOrganizations < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelOrganizations' }.freeze

        # ---------------------------------------------------------------------
        # Roster cache
        # ---------------------------------------------------------------------
        #
        # What is cached is the PRE-FILTER roster — the full `build_org_data`
        # array, before #apply_filters, sorting and pagination. Filtering,
        # sorting and paging then run per request against the cached array, so
        # ONE entry serves every filter/page/search combination and the filters
        # stay exact. Caching the paginated response instead (keyed on
        # page+status+sync_status+search) would have a near-zero hit rate.
        #
        # The expensive part is #build_org_data, not the slicing: per org it
        # does a full Customer load for `owner` (an N+1), two sorted-set
        # cardinality reads and two BillingService sync computations. Caching
        # the post-build array amortizes all of it, which is also why
        # `owner_email` stays in the cached row — the search matches on it, and
        # a lazy owner load would reintroduce the N+1 on every search.
        #
        # Mechanism: `Familia.dbclient` + SETEX of a JSON blob, the established
        # in-repo idiom (see the DNS cache in
        # lib/onetime/domain_validation/sender_strategies/base_strategy.rb and
        # Billing::WebhookSyncFlag). Familia's `class_json_string` — the other
        # TTL-cache idiom here (Billing::Plan.catalog_synced_at) — is a
        # Horreum class-level declaration and is not available to a Logic
        # object.
        #
        # CACHE_SHAPE is part of the KEY, not the payload: bumping it whenever
        # #build_org_data's keys change makes a deploy read a fresh key and lets
        # the old one expire on its own. This matters because the frontend Zod
        # contract degrades a mismatched payload to an EMPTY table — a
        # stale-shaped entry surviving a deploy would silently blank the admin
        # table rather than fail loudly.
        CACHE_SHAPE = 'v1'
        CACHE_KEY   = "colonel:organizations:list:#{CACHE_SHAPE}".freeze
        CACHE_TTL   = 90 # seconds

        # Upper bound on the serialized roster we are willing to push through a
        # single Redis string. A large fleet (one default workspace per account)
        # would serialize to tens of megabytes, and GET-ing that on every admin
        # page view is worse than the scan it replaces. Over the bound we log
        # and skip the write: the endpoint stays correct and simply behaves as
        # it did before this cache existed. The durable fix for that scale is an
        # index-backed endpoint (see ListStripeOrganizations), not a bigger blob.
        CACHE_MAX_BYTES = 8 * 1024 * 1024

        attr_reader :organizations,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :status_filter,
          :sync_status_filter,
          :search_term,
          :refresh,
          :cache_hit,
          :cache_generated_at

        def process_params
          @page               = (params['page'] || 1).to_i
          @per_page           = (params['per_page'] || 50).to_i
          @per_page           = 100 if @per_page > 100 # Max 100 per page
          @page               = 1 if @page < 1
          @status_filter      = params['status']      # subscription_status filter
          @sync_status_filter = params['sync_status'] # synced, potentially_stale, unknown
          @search_term        = params['search'].to_s.strip # objid/extid exact, or email substring
          # Explicit operator bypass. An operator who reconciles an org and
          # reloads must not be served the pre-mutation roster.
          @refresh            = truthy?(params['refresh'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Seed the MISS shape for both paths: `details.cache` is a required
          # member of the frontend Zod contract, so it must be present even
          # when the cache read AND write both blow up (filtered path) and on
          # the cache-free paged path, which never touches the cache at all.
          @cache_hit          = false
          @cache_generated_at = Familia.now.to_i

          if active_filters?
            # Full roster (from cache when possible — see the cache notes
            # above), filtered in memory, then sorted and paginated.
            org_data_list = apply_filters(filtered_roster)

            @total_count = org_data_list.size

            # Sort by created timestamp (most recent first)
            org_data_list.sort_by! { |data| -(data[:created] || 0) }

            start_idx      = (@page - 1) * @per_page
            @organizations = org_data_list[start_idx, @per_page] || []
          else
            # Default admin view: page straight off the instances sorted set,
            # loading only this page's orgs. total_count is the set
            # cardinality (ZCARD), so the pagination envelope reflects the
            # full population even though only one page is ever loaded.
            @total_count   = Onetime::Organization.instances.size
            @organizations = paged_roster
          end

          @total_pages = (@total_count.to_f / @per_page).ceil

          success_data
        end

        private

        # One page of the roster, straight off the instances sorted set — no
        # cache involved.
        #
        # The set orders by last-modified timestamp, so revrange(start, end)
        # returns exactly this page of most-recently-touched orgs (highest
        # scores first) without scanning or loading the full set. Rows keep
        # that recency order: page 1 is the @per_page most recently modified
        # orgs, page 2 the next tranche, and so on.
        #
        # @return [Array<Hash>] one symbol-keyed row per org on this page
        def paged_roster
          start_idx = (@page - 1) * @per_page
          end_idx   = start_idx + @per_page - 1

          page_org_ids = Onetime::Organization.instances.revrange(start_idx, end_idx)
          page_orgs    = Onetime::Organization.load_multi(page_org_ids).compact
          page_orgs.map { |org| build_org_data(org) }
        end

        # Pre-filter roster for a filtered/search request, from cache when
        # possible (see the cache notes above).
        #
        # Sets @cache_hit / @cache_generated_at as a side effect so
        # #success_data can report the cache state on the wire. Both were
        # seeded with the MISS shape in #process, so they hold sane values
        # even when the read AND the write both blow up.
        #
        # @return [Array<Hash>] one symbol-keyed row per organization
        def filtered_roster
          unless refresh
            cached = read_cache
            if cached
              @cache_hit          = true
              @cache_generated_at = cached[:generated_at]
              return cached[:organizations]
            end
          end

          all_org_ids   = Onetime::Organization.instances.to_a
          all_orgs      = Onetime::Organization.load_multi(all_org_ids).compact
          org_data_list = all_orgs.map { |org| build_org_data(org) }

          @cache_generated_at = Familia.now.to_i
          write_cache(org_data_list, @cache_generated_at)

          org_data_list
        end

        # @return [Boolean] true if any filter or search term is active
        def active_filters?
          (status_filter && !status_filter.empty?) ||
            (sync_status_filter && !sync_status_filter.empty?) ||
            (search_term && !search_term.empty?)
        end

        # Read the cached roster.
        #
        # Parsed with symbolize_names so the cache-HIT path hands back exactly
        # the symbol-keyed rows #build_org_data produces — #apply_filters,
        # #matches_search? and the created-descending sort all index with
        # symbols, and string keys would silently make every filter match
        # nothing. The key set is closed (our own field list), so symbolizing
        # cannot be driven by untrusted input.
        #
        # @return [Hash, nil] { generated_at:, organizations: } or nil on a miss
        def read_cache
          raw = Familia.dbclient.get(CACHE_KEY)
          return nil if raw.nil? || raw.empty?

          payload = JSON.parse(raw, symbolize_names: true)
          return nil unless payload.is_a?(Hash)

          rows = payload[:organizations]
          return nil unless rows.is_a?(Array)

          { generated_at: payload[:generated_at].to_i, organizations: rows }
        rescue StandardError => ex
          # A cache failure must never break the endpoint — fall through to the
          # uncached computation.
          OT.le '[ListOrganizations] roster cache read failed',
            {
              exception: ex,
              message: ex.message,
              key: CACHE_KEY,
            }
          nil
        end

        # Write the roster to the cache. Best-effort: a failure is logged and
        # swallowed, leaving the response untouched.
        def write_cache(org_data_list, generated_at)
          blob = JSON.generate({ generated_at: generated_at, organizations: org_data_list })

          if blob.bytesize > CACHE_MAX_BYTES
            OT.le '[ListOrganizations] roster too large to cache',
              {
                bytes: blob.bytesize,
                limit: CACHE_MAX_BYTES,
                organizations: org_data_list.size,
              }
            return nil
          end

          Familia.dbclient.setex(CACHE_KEY, CACHE_TTL, blob)
        rescue StandardError => ex
          OT.le '[ListOrganizations] roster cache write failed',
            {
              exception: ex,
              message: ex.message,
              key: CACHE_KEY,
            }
          nil
        end

        # Matches the sibling colonel logic classes (repair_domain,
        # transfer_domain, purge_dlq) rather than introducing a shared helper.
        def truthy?(value)
          %w[true 1 yes on].include?(value.to_s.strip.downcase)
        end

        def build_org_data(org)
          owner = org.owner

          {
            org_id: org.objid,
            extid: org.extid,
            display_name: org.display_name,
            # FULL addresses (colonel-only, scope=internal). The admin table
            # obscures every email by default and reveals on interaction via
            # RevealEmail.vue, so all three addresses here — contact, owner and
            # billing — arrive raw and are masked client-side. This replaces the
            # earlier server-side masking of contact_email/owner_email, which was
            # inconsistent (billing_email was always sent raw) and irreversible
            # (the operator could never see the address even when support work
            # required it).
            contact_email: org.contact_email,
            owner_id: org.owner_id,
            owner_email: owner&.email,
            member_count: org.member_count,
            domain_count: org.domain_count,
            is_default: org.is_default.to_s == 'true',
            created: org.created.to_i,
            updated: org.updated&.to_i,
            # Billing fields
            planid: org.planid,
            stripe_customer_id: org.stripe_customer_id,
            stripe_subscription_id: org.stripe_subscription_id,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end&.to_s,
            billing_email: org.billing_email,
            # Computed sync health
            sync_status: compute_sync_status(org),
            sync_status_reason: compute_sync_status_reason(org),
          }
        end

        # Compute sync health status based on billing state consistency
        #
        # @param org [Onetime::Organization] Organization to check
        # @return [String] 'synced', 'potentially_stale', or 'unknown'
        # @see Billing::BillingService.compute_sync_status
        def compute_sync_status(org)
          Billing::BillingService.compute_sync_status(org)
        end

        # Provide human-readable reason for sync status
        #
        # @param org [Onetime::Organization] Organization to check
        # @return [String, nil] Reason for the sync status
        # @see Billing::BillingService.compute_sync_status_reason
        def compute_sync_status_reason(org)
          Billing::BillingService.compute_sync_status_reason(org)
        end

        def apply_filters(org_data_list)
          result = org_data_list

          # Filter by subscription status
          if status_filter && !status_filter.empty?
            result = result.select { |data| data[:subscription_status] == status_filter }
          end

          # Filter by sync status
          if sync_status_filter && !sync_status_filter.empty?
            result = result.select { |data| data[:sync_status] == sync_status_filter }
          end

          # Free-text search: objid/extid exact match, OR case-insensitive
          # substring across contact/owner/billing emails. Applied in the same
          # in-memory pass as the other filters (see #process scaling note).
          if search_term && !search_term.empty?
            result = result.select { |data| matches_search?(data) }
          end

          result
        end

        # objid/extid are exact-equality arms; display_name and the three emails
        # are substring arms. Every substring field is nil-safe (.to_s) —
        # display_name/owner_email/billing_email can all be nil.
        #
        # display_name joined the substring arms when the name became the list's
        # leading column: searching for the org you can see by the name you can
        # see is the obvious expectation, and without it the box silently
        # returned nothing for the most natural query an operator would type.
        def matches_search?(data)
          return true if data[:org_id].to_s == search_term
          return true if data[:extid].to_s == search_term

          needle = search_term.downcase
          [:display_name, :contact_email, :owner_email, :billing_email].any? do |key|
            data[key].to_s.downcase.include?(needle)
          end
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
              },
              filters: {
                status: status_filter,
                sync_status: sync_status_filter,
                search: search_term,
              },
              # Roster cache state, so the UI can show "updated <n> ago" and
              # offer an explicit refresh. `generated_at` is the unix second the
              # roster was BUILT (not when it was served), so it keeps its value
              # across cache hits. Symbol keys here match the rest of this
              # envelope; they serialize to the string keys the Zod contract
              # declares.
              cache: {
                cached: cache_hit,
                generated_at: cache_generated_at,
                ttl: CACHE_TTL,
              },
            },
          }
        end
      end
    end
  end
end

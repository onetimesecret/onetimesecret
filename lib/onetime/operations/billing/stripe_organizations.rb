# lib/onetime/operations/billing/stripe_organizations.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Billing
      # Bounded, index-backed listing of every organization that carries a
      # Stripe customer id — the SINGLE implementation.
      #
      # Adapters:
      #   - `GET /api/colonel/billing/stripe-organizations`
      #     (ColonelAPI::Logic::Colonel::ListStripeOrganizations)
      #   - `bin/ots billing orgs stripe`
      #
      # ## Why the index, not a scan (CONTRACT 6)
      #
      # `Onetime::Organization` already declares
      # `unique_index :stripe_customer_id, :stripe_customer_id_index`, which
      # Familia materialises as the class-level HashKey
      # `Organization.stripe_customer_id_index` (Redis key
      # `organization:stripe_customer_id_index`, field = `cus_…`, value = the org
      # objid). This op reads THAT — HLEN for the population count, HSCAN for the
      # entries — and hydrates ONLY the requested page through
      # `Organization.load_multi`. It never enumerates `Organization.instances`
      # (the slow path `ListOrganizations` still uses) and it never adds a second
      # index.
      #
      # Stripe customer ids live on Organization, NOT on Customer:
      # `Customer#stripe_customer_id` is a deprecated v1 field with no index. A
      # "customers with billing" view must therefore be derived from org
      # membership, not queried directly — hence organizations here.
      #
      # ## Ordering and bounding
      #
      # HSCAN has no defined order, so the entries are sorted by
      # `stripe_customer_id` (ascending) to give pagination a STABLE key.
      # Created-desc ordering would require hydrating the whole population on
      # every request, which is exactly what this op exists to avoid.
      #
      # The scan stops at {MAX_INDEX_ENTRIES}; when it does, `capped` is true and
      # `total_count` UNDERSTATES the population. Surface that — do not render
      # "showing X of Y" as if Y were exact.
      #
      # ## Stale entries
      #
      # An index entry whose org no longer loads is a real (and interesting)
      # integrity signal, but it has no extid/display_name to render. Such rows
      # are dropped from `organizations` and counted in `stale_count` for the
      # page, so a page can contain fewer rows than `per_page`.
      #
      # READ-ONLY: emits NO AdminAuditEvent (CONTRACT 4).
      class StripeOrganizations
        # Hard bound on how many index entries a single request will read.
        MAX_INDEX_ENTRIES = 5_000

        # HSCAN batch size — round-trips vs. per-call blocking.
        SCAN_BATCH = 500

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        # @!attribute organizations [r] Array<Hash> — one row per hydrated org.
        # @!attribute total_count [r] Integer — matching index entries (bounded).
        # @!attribute capped [r] Boolean — true when the scan hit the bound.
        # @!attribute stale_count [r] Integer — index entries on THIS page whose
        #   organization no longer loads.
        # @!attribute indexed_total [r] Integer — HLEN of the whole index,
        #   independent of any search filter.
        Result = Data.define(
          :organizations,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :capped,
          :stale_count,
          :indexed_total,
          :search,
        )

        # @param page [Integer] 1-based page number.
        # @param per_page [Integer] page size, clamped to 1..{MAX_PER_PAGE}.
        # @param search [String, nil] filter on the Stripe customer id. A bare
        #   term is treated as a substring (wrapped in `*`); a term already
        #   containing a glob metacharacter (`*` or `?`) is passed through
        #   verbatim to HSCAN MATCH.
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE, search: nil)
          @page     = page.to_i
          @page     = 1 if @page < 1
          @per_page = per_page.to_i
          @per_page = DEFAULT_PER_PAGE if @per_page < 1
          @per_page = MAX_PER_PAGE if @per_page > MAX_PER_PAGE
          @search   = search.to_s.strip
        end

        # @return [Result]
        def call
          index         = Onetime::Organization.stripe_customer_id_index
          indexed_total = safe_field_count(index)

          entries, capped = scan_entries(index)
          entries.sort_by! { |stripe_id, _objid| stripe_id.to_s }

          total_count = entries.size
          total_pages = (total_count.to_f / @per_page).ceil

          start_idx  = (@page - 1) * @per_page
          page_slice = entries[start_idx, @per_page] || []

          orgs_by_objid = hydrate(page_slice.map(&:last))

          stale_count = 0
          rows        = page_slice.filter_map do |stripe_id, objid|
            org = orgs_by_objid[objid.to_s]
            if org.nil?
              stale_count += 1
              OT.lw "[Billing::StripeOrganizations] stale index entry #{stripe_id} -> #{objid}"
              next
            end

            build_row(org, stripe_id)
          end

          Result.new(
            organizations: rows,
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
            capped: capped,
            stale_count: stale_count,
            indexed_total: indexed_total,
            search: @search,
          )
        end

        private

        # @return [Array(Array<Array(String, String)>, Boolean)] entries + capped
        def scan_entries(index)
          entries = []
          capped  = false

          index.each(matching: match_pattern, batch_size: SCAN_BATCH) do |stripe_id, objid|
            entries << [stripe_id.to_s, objid.to_s]
            if entries.size >= MAX_INDEX_ENTRIES
              capped = true
              break
            end
          end

          [entries, capped]
        rescue StandardError => ex
          OT.le '[Billing::StripeOrganizations] index scan failed',
            { exception: ex, message: ex.message }
          [[], false]
        end

        # nil means "no MATCH" (HSCAN returns everything).
        def match_pattern
          return nil if @search.empty?
          return @search if @search.match?(/[*?\[\]]/)

          "*#{@search}*"
        end

        def safe_field_count(index)
          index.field_count.to_i
        rescue StandardError
          0
        end

        # One pipelined load_multi for the page's objids.
        def hydrate(objids)
          return {} if objids.empty?

          Onetime::Organization.load_multi(objids).compact
            .each_with_object({}) { |org, acc| acc[org.objid.to_s] = org }
        rescue StandardError => ex
          OT.le '[Billing::StripeOrganizations] page hydration failed',
            { exception: ex, message: ex.message }
          {}
        end

        # Row shape mirrors the billing subset of ListOrganizations' rows so the
        # admin console can reuse its cell renderers. Emails are FULL addresses
        # (colonel-only, scope=internal) and are masked client-side by
        # RevealEmail.vue, matching ListOrganizations.
        def build_row(org, stripe_id)
          {
            org_id: org.objid,
            extid: org.extid,
            display_name: org.display_name,
            owner_email: safe_owner_email(org),
            billing_email: org.billing_email,
            planid: org.planid,
            stripe_customer_id: stripe_id,
            stripe_subscription_id: org.stripe_subscription_id,
            subscription_status: org.subscription_status,
            subscription_period_end: blank_to_nil(org.subscription_period_end),
            sync_status: compute_sync_status(org),
            created: org.created&.to_i,
            updated: org.updated&.to_i,
          }
        end

        # Owner resolution is one extra load per ROW (bounded by per_page, max
        # 100) — never per population.
        def safe_owner_email(org)
          org.owner&.email
        rescue StandardError
          nil
        end

        # Emitted as a String (or nil) so the field types match the rest of the
        # billing row; the underlying field is a Unix timestamp.
        def blank_to_nil(value)
          str = value.to_s
          str.empty? ? nil : str
        end

        # Reuses the incumbent computation when the billing app is loaded; a
        # billing-disabled deployment reports nil rather than guessing.
        def compute_sync_status(org)
          return nil unless defined?(::Billing::BillingService)

          ::Billing::BillingService.compute_sync_status(org)
        rescue StandardError
          nil
        end
      end
    end
  end
end

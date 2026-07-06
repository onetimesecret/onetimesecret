# apps/web/auth/operations/customers/list.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # List customers for the admin surfaces (colonel API + `bin/ots customers`).
      #
      # This is the ONE implementation of "enumerate customers, optionally filtered
      # by role, paginated." Both the colonel `ListUsers` Logic class and the CLI
      # `customers list` command are thin adapters over it. It is read-only, so it
      # writes no audit event (only mutating ops audit).
      #
      # ## Pagination: index-backed, not load-all-then-slice (epic #20)
      #
      # The unfiltered path is the pagination TEMPLATE every later admin list
      # endpoint copies. It reads exactly one page directly out of the
      # `Customer.instances` sorted set with `ZREVRANGE (page-1)*per_page ...`
      # and loads only that page via `load_multi`. It never loads the whole
      # customer set into Ruby to slice it (the #2211 blocking-enumeration
      # incident: no unbounded `KEYS`/`SMEMBERS`/load-all on the request path).
      #
      # ### Ordering is index-native (deliberate change, epic #20 CONTRACT 6)
      #
      # `Customer.instances` is scored by save time (`instances.add(self, Familia.now)`
      # on every save), so `ZREVRANGE` yields **most-recently-modified first**. The
      # previous colonel implementation loaded everything and sorted by `created`
      # descending. Switching to the index-native order is an accepted, deliberate
      # consequence of paginating at the source — it is what makes single-page reads
      # possible. `total_count` / `total_pages` are unchanged; only within-page order
      # differs.
      #
      # ### Role filter (bounded cursor SSCAN — epic #20 CONTRACT 8, #2211)
      #
      # When a role filter is supplied we read the role's membership from the
      # `role_index` multi-index, but via a NON-BLOCKING cursor SSCAN over the
      # role set — never a blocking `SMEMBERS` of a set whose size we do not
      # control (the #2211 incident). On the request path (paginated, i.e. not
      # `:all`) the scan also stops after at most `ROLE_FILTER_SCAN_LIMIT`
      # members, so a filter on the catch-all `customer` role — whose set grows
      # with the entire customer base — can NEVER load the whole population into
      # Ruby on a single request. The operational roles (colonel/admin/staff) are
      # far below that cap, so their filter stays exact and index-backed.
      #
      # Trade-off (documented, deliberate): beyond the cap the catch-all
      # `customer` filter returns a bounded window rather than an exactly
      # paginated full set. A per-role SORTED index that lets the filtered path
      # `ZREVRANGE` a single page (like the unfiltered path) is the follow-up for
      # exact deep pagination of a high-cardinality role. This replaces the prior
      # `find_all_by_role` — a blocking `SMEMBERS` + load-all-then-slice, which
      # was the residual request-path unbounded enumeration flagged on the slice.
      #
      class List
        # Immutable result. `customers` is a page of loaded Onetime::Customer
        # objects; the adapters format them for their respective surfaces (the
        # colonel API enriches with secret counts, the CLI groups by domain).
        Result = Data.define(
          :customers,     # Array<Onetime::Customer> — the requested page
          :total_count,   # Integer — total matching customers (across all pages)
          :page,          # Integer — clamped page number
          :per_page,      # Integer — clamped page size (0 when :all requested)
          :total_pages,   # Integer — ceil(total_count / per_page), 1 when :all
          :role,          # String, nil — the applied role filter (nil = none)
        )

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE     = 100

        # Per-round-trip COUNT hint for the non-blocking role_index cursor SSCAN
        # (mirrors the maintenance jobs' SCAN_COUNT). Bounds work per Redis
        # round-trip; it is a hint, not a hard page size.
        SCAN_COUNT = 100

        # Request-path cap on how many role_index members the filtered path loads
        # into Ruby. Bounds the degenerate `role=customer` case (that set grows
        # with the whole customer base) so a single request can never enumerate
        # the entire population (#2211 / epic #20 CONTRACT 8). Operational roles
        # sit far below this, so their filter stays exact. `:all` (the off-request
        # CLI view) is exempt — it reads the whole set, still via the cursor SSCAN.
        ROLE_FILTER_SCAN_LIMIT = 10_000

        # @param page [Integer] 1-based page number (clamped to >= 1)
        # @param per_page [Integer, :all] page size (clamped to 1..MAX_PER_PAGE),
        #   or :all to load every matching customer in one shot. `:all` is for the
        #   off-request CLI grouping view only — never pass it from a request handler.
        # @param role [String, nil] optional role filter (blank string treated as nil)
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE, role: nil)
          @all      = (per_page == :all)
          @page     = [page.to_i, 1].max
          @per_page = @all ? 0 : clamp_per_page(per_page)
          role      = role.to_s.strip
          @role     = role.empty? ? nil : role
        end

        # @return [Result]
        def call
          @role ? call_filtered : call_unfiltered
        end

        private

        def clamp_per_page(value)
          per_page = value.to_i
          per_page = DEFAULT_PER_PAGE if per_page <= 0
          [per_page, MAX_PER_PAGE].min
        end

        # Unfiltered: page straight out of the instances sorted set (index-native
        # order), loading only the requested page.
        def call_unfiltered
          total_count = Onetime::Customer.instances.element_count

          if @all
            # `:all` is the off-request CLI grouping view. Enumerate in the
            # sorted set's natural (ascending save-time) order — matching the
            # incumbent `Customer.instances.all` — so the CLI grouping stays
            # byte-identical. Order is irrelevant to the caller's grouping; the
            # descending index-native order is reserved for the paginated view.
            objids = Onetime::Customer.instances.range(0, -1)
            return build_result(load(objids), total_count)
          end

          start_idx = (@page - 1) * @per_page
          end_idx   = start_idx + @per_page - 1
          objids    = Onetime::Customer.instances.revrange(start_idx, end_idx)

          build_result(load(objids), total_count)
        end

        # Role-filtered: read the role's members from the role_index via a
        # bounded, non-blocking cursor SSCAN (see class docs), then order + slice.
        # On the request path the read is capped at ROLE_FILTER_SCAN_LIMIT so an
        # unbounded role set is never fully loaded; `:all` (off-request) reads all.
        def call_filtered
          limit       = @all ? nil : ROLE_FILTER_SCAN_LIMIT
          matches     = load(scan_role_member_ids(@role, limit: limit))
          # Preserve the incumbent within-page ordering for the filtered path
          # (created descending) — the role_index is an unordered set, so there is
          # no index-native order to read here.
          matches.sort_by! { |cust| -(cust.created || 0).to_f }
          total_count = matches.size

          page = if @all
            matches
          else
            start_idx = (@page - 1) * @per_page
            end_idx   = start_idx + @per_page - 1
            matches[start_idx..end_idx] || []
          end

          build_result(page, total_count)
        end

        # Non-blocking cursor SSCAN of a role_index set, collecting member objids.
        # Bounded per round-trip by SCAN_COUNT and, when `limit` is set (the
        # request path), capped at `limit` total members — so the catch-all
        # `customer` role can never be fully enumerated on a request (#2211 /
        # epic #20 CONTRACT 8). `limit: nil` reads the whole set (the off-request
        # `:all` view), still via the cursor rather than a blocking SMEMBERS.
        def scan_role_member_ids(role, limit:)
          dbkey    = Onetime::Customer.role_index_for(role).dbkey
          dbclient = Onetime::Customer.dbclient
          objids   = []

          dbclient.sscan_each(dbkey, count: SCAN_COUNT) do |objid|
            objids << objid
            break if limit && objids.size >= limit
          end

          objids
        end

        def load(objids)
          Onetime::Customer.load_multi(objids).compact
        end

        def build_result(customers, total_count)
          total_pages = if @all || @per_page.zero?
            total_count.positive? ? 1 : 0
          else
            (total_count.to_f / @per_page).ceil
          end

          Result.new(
            customers: customers,
            total_count: total_count,
            page: @page,
            per_page: @per_page,
            total_pages: total_pages,
            role: @role,
          )
        end
      end
    end
  end
end

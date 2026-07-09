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
      # ### Search (bounded email HSCAN + exact identifier lookups)
      #
      # "Look up the account that just emailed you" is the #1 admin action, so
      # the op supports a free-text `search` term. It resolves three ways and
      # merges the results (deduped by objid):
      #
      # 1. Email substring — a bounded cursor HSCAN over the
      #    `customer:email_index` hash (email -> objid, emails stored lowercase)
      #    with a server-side `*term*` glob — the same scan-with-match mechanism
      #    the sessions listing uses, but against the index instead of the
      #    keyspace. It never enumerates customer objects. Bounded twice
      #    (CONTRACT 8 / #2211): matches are capped at SEARCH_MATCH_LIMIT and the
      #    scan stops after SEARCH_SCAN_ROUNDS round-trips, so a no-match search
      #    over a huge customer base can never turn one request into an unbounded
      #    walk. The glob term is escaped, so user input cannot inject pattern
      #    syntax.
      # 2. External id (extid, `ur…s`) — an exact `find_by_extid` on the
      #    extid_lookup unique index.
      # 3. Internal id (objid, the UUID primary key) — an exact
      #    `find_by_identifier`.
      #
      # The two identifier lookups are O(1) unique-index gets, never scans, so
      # they add no enumeration cost and are attempted on every search — a
      # support agent can paste an extid or objid straight into the box and the
      # non-matching lookups simply return nothing (a garbage term is rescued).
      # Search composes with the role filter (applied in Ruby on the already
      # -bounded matches) and is paginated in memory like the filtered path.
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

        # Cap on how many email-index MATCHES the search path collects. A page
        # is at most MAX_PER_PAGE rows, so 1k matches is already 10 pages of
        # results for a support lookup — anything broader is a filter problem,
        # not a pagination problem.
        SEARCH_MATCH_LIMIT = 1_000

        # Cap on HSCAN round-trips for one search. With SCAN_COUNT=100 per
        # round-trip this bounds the index walk at ~100k entries examined even
        # when the term matches nothing (HSCAN's MATCH filters server-side, so
        # a no-match term would otherwise walk the entire index).
        SEARCH_SCAN_ROUNDS = 1_000

        # @param page [Integer] 1-based page number (clamped to >= 1)
        # @param per_page [Integer, :all] page size (clamped to 1..MAX_PER_PAGE),
        #   or :all to load every matching customer in one shot. `:all` is for the
        #   off-request CLI grouping view only — never pass it from a request handler.
        # @param role [String, nil] optional role filter (blank string treated as nil)
        # @param search [String, nil] optional search term: an email substring
        #   (case-insensitive) and/or an exact extid / objid. Blank string
        #   treated as nil. Composes with the role filter.
        def initialize(page: 1, per_page: DEFAULT_PER_PAGE, role: nil, search: nil)
          @all      = (per_page == :all)
          @page     = [page.to_i, 1].max
          @per_page = @all ? 0 : clamp_per_page(per_page)
          role      = role.to_s.strip
          @role     = role.empty? ? nil : role
          search    = search.to_s.strip
          @search   = search.empty? ? nil : search
        end

        # @return [Result]
        def call
          return call_search if @search

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

        # Search: bounded cursor HSCAN over the email unique index PLUS exact
        # extid / objid lookups (see class docs), merged and deduped by objid,
        # then ordered + sliced exactly like the filtered path. The role filter,
        # when also present, is applied in Ruby on the loaded matches — the match
        # set is already bounded, so this stays cheap.
        def call_search
          matches = load(scan_email_index_matches(@search))
          merge_identifier_matches(matches)
          matches.select! { |cust| cust.role.to_s == @role } if @role
          # Same within-page ordering as the filtered path (created descending);
          # the email index is a hash, so there is no index-native order here.
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

        # Non-blocking cursor HSCAN of the email_index hash (email -> objid),
        # matching `*term*` server-side against the lowercased stored emails.
        # Doubly bounded: stops at SEARCH_MATCH_LIMIT collected matches AND at
        # SEARCH_SCAN_ROUNDS round-trips (see the constants above).
        def scan_email_index_matches(term)
          dbkey    = Onetime::Customer.email_index.dbkey
          dbclient = Onetime::Customer.dbclient
          pattern  = "*#{glob_escape(term.downcase)}*"
          objids   = []
          cursor   = '0'
          rounds   = 0

          loop do
            cursor, entries = dbclient.hscan(dbkey, cursor, match: pattern, count: SCAN_COUNT)
            entries.each { |_email, objid| objids << objid }
            rounds += 1

            break if cursor == '0'
            break if objids.size >= SEARCH_MATCH_LIMIT
            break if rounds >= SEARCH_SCAN_ROUNDS
          end

          objids.first(SEARCH_MATCH_LIMIT)
        end

        # Append the exact extid / objid lookups for the search term to the
        # already-loaded email matches, skipping any customer already present
        # (deduped by objid). Both lookups are O(1) unique-index gets — never a
        # scan — so they cost nothing when they miss. A malformed term (e.g. a
        # value the identifier index rejects) is rescued to nil rather than
        # failing the whole search.
        def merge_identifier_matches(matches)
          seen = matches.map(&:objid)

          identifier_lookups(@search).each do |cust|
            next if seen.include?(cust.objid)

            matches << cust
            seen << cust.objid
          end
        end

        # Exact-match customer lookups by external id (extid) and internal id
        # (objid). Returns a (possibly empty) array of Onetime::Customer.
        def identifier_lookups(term)
          [
            safe_lookup { Onetime::Customer.find_by_extid(term) },
            safe_lookup { Onetime::Customer.find_by_identifier(term) },
          ].compact
        end

        # A unique-index lookup on a free-text term can raise on input the index
        # cannot parse; swallow that so it degrades to "no match" rather than a
        # 500 on the search endpoint.
        def safe_lookup
          yield
        rescue StandardError
          nil
        end

        # Escape Redis glob metacharacters so a user-supplied term is always a
        # literal substring match, never pattern syntax.
        def glob_escape(term)
          term.gsub(/[\*\?\[\]\\]/) { |char| "\\#{char}" }
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

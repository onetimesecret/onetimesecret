# apps/api/colonel/logic/colonel/list_users.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'auth/operations/customers/list'

module ColonelAPI
  module Logic
    module Colonel
      # List Users
      #
      # @api Returns a paginated list of all users with obscured emails,
      #   roles, verification status, plan IDs, and secret counts. Supports
      #   optional role filtering, an optional email `search` term (bounded
      #   HSCAN over the email index — the same server-side search mechanism
      #   the sessions listing offers), and pagination via page/per_page
      #   params. Requires colonel role.
      class ListUsers < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelUsers' }.freeze

        attr_reader :users, :total_count, :page, :per_page, :total_pages, :role_filter, :search, :capped

        def process_params
          @page        = (params['page'] || 1).to_i
          @per_page    = (params['per_page'] || 50).to_i
          @per_page    = 100 if @per_page > 100 # Max 100 per page
          @page        = 1 if @page < 1
          @role_filter = sanitize_plain_text(params['role']) # Optional: filter by role
          @search      = sanitize_plain_text(params['search'], max_length: 255) if params['search']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          # Single implementation: index-backed pagination via the shared op
          # (Auth::Operations::Customers::List). This replaces the former
          # load-ALL-customers-then-slice-in-Ruby pattern with an index-native
          # ZRANGE over Customer.instances that loads only the requested page
          # (epic #20; #2211 no-blocking-enumeration).
          #
          # DELIBERATE ORDERING CHANGE (epic #20 CONTRACT 6): the page is now
          # ordered most-recently-MODIFIED first (the native score of the
          # instances sorted set) instead of most-recently-CREATED first. This is
          # what makes single-page reads possible; total_count / total_pages are
          # unchanged. See the op for details.
          result = Auth::Operations::Customers::List.new(
            page: page,
            per_page: per_page,
            role: role_filter,
            search: search,
          ).call

          @total_count = result.total_count
          @total_pages = result.total_pages
          @capped      = result.capped

          # Format user data (anonymous customers are dropped from the list, as
          # before; total_count above still counts them, matching prior behavior).
          @users = result.customers.map do |cust|
            next if cust.anonymous?

            {
              user_id: cust.extid,
              extid: cust.extid,
              # FULL address (colonel-only, scope=internal). The admin table
              # obscures it client-side and reveals on interaction — RevealEmail.vue.
              email: cust.email,
              role: cust.role,
              verified: cust.verified?,
              suspended: cust.suspended?,
              created: cust.created,
              last_login: cust.last_login,
              # Authoritative plan lives on the customer's Organization, not the
              # deprecated Customer#planid field (which drifts — a legacy value
              # like "identity" survives on the customer hash even after the org
              # moved to team_plus_v1). Resolve the billing org's planid per row,
              # mirroring GetUserDetails#billing_organization; fall back to the
              # legacy field only when the customer participates in no org. This
              # is a bounded per-row org load (<= per_page rows, ~1 org each),
              # consistent with the per-row secrets_count read above.
              planid: resolve_planid(cust),
              # secrets_count is now read from the maintained per-customer
              # secrets_active counter (#60), resolving the TODO(#60) that #20
              # left in place. This replaces the former per-request SCAN over
              # every `secret:*:object` key (10k-capped, so any owner past 10k
              # secrets was silently undercounted — the #2211 blocking/unbounded
              # enumeration family). The SCAN now lives OFF the request path in
              # SecretCountReconcileJob; here we do a single O(1) counter read
              # per row on the already-bounded page (<= per_page), never an
              # enumeration. Counters are Familia::Counter objects — coerce to
              # Integer so JSON does not try to .each over an opaque Counter.
              secrets_count: cust.respond_to?(:secrets_active) ? cust.secrets_active.to_i : 0,
              secrets_created: cust.respond_to?(:secrets_created) ? cust.secrets_created.to_i : 0,
              secrets_shared: cust.respond_to?(:secrets_shared) ? cust.secrets_shared.to_i : 0,
            }
          end.compact

          success_data
        end

        private

        # Resolve a customer's effective plan id from their Organization.
        #
        # Selection mirrors GetUserDetails#billing_organization: the first org
        # with a Stripe customer id (the one actually billed), else the default
        # workspace, else the first org. Returns that org's planid. Falls back
        # to the legacy Customer#planid only when the customer has no org (e.g.
        # legacy Redis-only seed accounts). Any load failure degrades to the
        # legacy field rather than 500-ing the list.
        #
        # @param cust [Onetime::Customer]
        # @return [String, nil]
        def resolve_planid(cust)
          return cust.planid unless cust.respond_to?(:organization_instances)

          # organization_instances is the Familia participation reverse accessor
          # (config_name "organization" + "_instances"); it returns already-loaded,
          # existence-checked Organization objects (load_multi.compact). There is
          # no bare `organizations` method — see organization_loader.rb.
          orgs = cust.organization_instances.to_a.reject(&:archived?)
          return cust.planid if orgs.empty?

          billing_org = orgs.find { |org| !org.stripe_customer_id.to_s.empty? } ||
                        orgs.find(&:is_default) ||
                        orgs.first
          billing_org.planid
        rescue StandardError
          cust.planid
        end

        def success_data
          {
            record: {},
            details: {
              users: users,
              pagination: {
                page: page,
                per_page: per_page,
                total_count: total_count,
                total_pages: total_pages,
                # true when the role/search scan hit its request-path cap, so
                # total_count understates the population (more rows exist unseen).
                capped: capped,
                role_filter: role_filter,
                search: search,
              },
            },
          }
        end
      end
    end
  end
end

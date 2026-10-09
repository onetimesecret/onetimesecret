# apps/api/colonel/logic/colonel/list_users.rb
#
# frozen_string_literal: true

require 'onetime/rodauth_admin'

require_relative '../base'
require 'auth/operations/customers/list'

module ColonelAPI
  module Logic
    module Colonel
      # List Users
      #
      # @api Returns a paginated list of all users with full email addresses
      #   (colonel-only; the admin table obscures them client-side via
      #   RevealEmail.vue), roles, verification status, plan IDs, and secret
      #   counts. Supports
      #   optional role filtering, an optional email `search` term (bounded
      #   HSCAN over the email index — the same server-side search mechanism
      #   the sessions listing offers), and pagination via page/per_page
      #   params. Requires colonel role.
      class ListUsers < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelUsers' }.freeze

        attr_reader :users,
          :total_count,
          :page,
          :per_page,
          :total_pages,
          :role_filter,
          :search,
          :capped,
          :orphaned_accounts

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

          @total_count       = result.total_count
          @total_pages       = result.total_pages
          @capped            = result.capped
          # Authdb rows an address-shaped search found with no customer record
          # behind them (full auth mode only; [] otherwise). Not users, not
          # counted in the pagination: the admin table renders them as a
          # separate "no customer record" notice so an orphan is visible
          # instead of an empty page. See Customers::List "Authdb fallback".
          @orphaned_accounts = result.orphaned_accounts

          # Format user data (anonymous customers are dropped from the list, as
          # before; total_count above still counts them, matching prior behavior).
          @users = result.customers.map do |cust|
            next if cust.anonymous?

            {
              user_id: cust.user_id,
              extid: cust.extid,
              # Outbound deep link to the matching Rodauth account in the
              # standalone admin (Onetime::RodauthAdmin); nil unless full auth
              # mode AND RODAUTH_ADMIN_URL are set.
              rodauth_admin_account_url: Onetime::RodauthAdmin.account_url(cust.extid),
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
              # moved to team_plus_v1). The three keys below say WHOSE plan this
              # is: the plan of the organization the customer owns and is
              # billed for (plan_source 'organization', billing_organization
              # names it), or the legacy customer field when they own none
              # (plan_source 'customer', billing_organization nil). A joined
              # organization's plan is never shown as this customer's — see
              # #resolve_plan. Bounded per-row org loads (<= per_page rows, a
              # few orgs each), consistent with the per-row counter reads below.
              **resolve_plan(cust),
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

        # The plan a customer row shows, labelled with where it comes from.
        #
        # Among the live organizations the customer OWNS: the first with a
        # Stripe customer id (the one actually billed), else their owned
        # default workspace (OrganizationLoader.owned_default_organization),
        # else their first owned org. That org's planid is the row's plan,
        # plan_source is 'organization' and billing_organization names it.
        #
        # Owned only, at every step. The old row-level scan ran the same
        # three-step selection over every membership, so a member of a paid
        # organization was listed on its plan — the Stripe-first step found
        # the joined org's Stripe customer, and the default-flag step found
        # its owner's default workspace. Neither is this customer's plan.
        #
        # A customer who owns no live organization shows the legacy
        # Customer#planid with plan_source 'customer' and no organization
        # (legacy Redis-only seed accounts; invited members who own nothing).
        # Any load failure degrades to that too rather than 500-ing the list.
        #
        # @param cust [Onetime::Customer]
        # @return [Hash] planid, plan_source, billing_organization
        def resolve_plan(cust)
          return legacy_plan(cust) unless cust.respond_to?(:organization_instances)

          # organization_instances is the Familia participation reverse accessor
          # (config_name "organization" + "_instances"); it returns already-loaded,
          # existence-checked Organization objects (load_multi.compact). There is
          # no bare `organizations` method — see organization_loader.rb.
          loader = Onetime::Application::OrganizationLoader
          owned  = loader.owned_organizations(cust)
          return legacy_plan(cust) if owned.empty?

          billing_org = owned.find { |org| !org.stripe_customer_id.to_s.empty? } ||
                        loader.owned_default_organization(cust, owned) ||
                        owned.first
          {
            planid: billing_org.planid,
            plan_source: 'organization',
            billing_organization: {
              extid: billing_org.extid,
              display_name: billing_org.display_name,
            },
          }
        rescue StandardError
          legacy_plan(cust)
        end

        def legacy_plan(cust)
          { planid: cust.planid, plan_source: 'customer', billing_organization: nil }
        end

        def success_data
          {
            record: {},
            details: {
              users: users,
              # Always present, [] when none, so the client schema is stable
              # across auth modes.
              orphaned_accounts: orphaned_accounts,
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

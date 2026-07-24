# apps/api/colonel/logic/colonel/list_stripe_organizations.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/billing/stripe_organizations'

module ColonelAPI
  module Logic
    module Colonel
      # List organizations that carry a Stripe customer id (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Billing::StripeOrganizations},
      # the single implementation (shared with `bin/ots billing orgs stripe`).
      #
      # ## Why a sibling endpoint and not a field on /billing/catalog
      #
      # {GetBillingCatalog} answers "does the declared catalog match Stripe?" —
      # an unpaginated, parameterless config-vs-live snapshot whose wire shape is
      # already frozen by a frontend Zod contract. This answers "which tenants are
      # actually billed?" — a paginated, searchable, index-backed roster with a
      # completely different refresh cadence and failure mode (a Stripe outage
      # degrades the catalog view; it does not touch this one). Folding a
      # paginated list into the catalog response would have forced every catalog
      # read to pay for an org scan and would have broken the pinned enum on
      # `details.source`. Two endpoints, two schemas, two caches.
      #
      # ## Request
      #
      # GET /api/colonel/billing/stripe-organizations
      #   ?page=1&per_page=50&search=cus_ABC
      #
      # `search` filters on the Stripe customer id ONLY (it is the index field,
      # so the filter runs server-side inside HSCAN MATCH). A bare term is
      # treated as a substring; a term containing `*` / `?` is used verbatim as a
      # glob. There is deliberately no name/email search — that would require
      # hydrating the whole population, which is the scan this endpoint replaces.
      #
      # ## Response
      #
      # {
      #   record: {},
      #   details: {
      #     organizations: [ {
      #       org_id:, extid:, display_name:, owner_email:, billing_email:,
      #       planid:, stripe_customer_id:, stripe_subscription_id:,
      #       subscription_status:, subscription_period_end:, sync_status:,
      #       created:, updated:
      #     } ],
      #     pagination: { page:, per_page:, total_count:, total_pages: },
      #     filters: { search: },
      #     capped: false,          # true => total_count understates the population
      #     stale_count: 0,         # index entries on THIS page whose org is gone
      #     indexed_total: 1234     # HLEN of the index, ignoring `search`
      #   }
      # }
      #
      # READ-ONLY: emits NO AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListStripeOrganizations < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelStripeOrganizations' }.freeze

        attr_reader :page, :per_page, :search_term, :result

        def process_params
          @page        = (params['page'] || 1).to_i
          @per_page    = (params['per_page'] || 50).to_i
          # Stripe customer ids are `cus_…` plus the operator's optional glob;
          # sanitize_identifier would strip `*`/`?`, so use the plain-text
          # sanitizer and let the op decide how to build the MATCH pattern.
          @search_term = sanitize_plain_text(params['search'], max_length: 128).to_s.strip
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Billing::StripeOrganizations.new(
            page: page,
            per_page: per_page,
            search: search_term,
          ).call

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              organizations: result.organizations,
              pagination: {
                page: result.page,
                per_page: result.per_page,
                total_count: result.total_count,
                total_pages: result.total_pages,
              },
              filters: {
                search: result.search,
              },
              capped: result.capped,
              stale_count: result.stale_count,
              indexed_total: result.indexed_total,
            },
          }
        end
      end
    end
  end
end

# apps/api/colonel/logic/colonel/get_billing_catalog.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/billing/catalog_drift'

module ColonelAPI
  module Logic
    module Colonel
      # Get Billing Catalog (drift view) — ticket #45, Phase 3.
      #
      # READ-ONLY surface over the billing plan catalog. Where
      # {GetAvailablePlans} returns ONE source (Stripe cache OR billing.yaml
      # config, whichever is populated), this class returns BOTH sides so the
      # admin console can show catalog/plan drift at a glance:
      #
      #   - config_plans — Billing::Plan.list_plans_from_config (billing.yaml,
      #     the declared catalog)
      #   - live_plans   — Billing::Plan.list_plans     (Stripe-synced Redis
      #     cache, what is actually live)
      #   - drift        — a computed summary of the difference (planids present
      #     on only one side, and planids present on both whose entitlements or
      #     limits diverge)
      #
      # Thin HTTP adapter over {Onetime::Operations::Billing::CatalogDrift}, the
      # single implementation (shared with `bin/ots billing catalog drift`),
      # which REUSES the incumbent Billing::Plan source (CONTRACT 5). It NEVER
      # writes, so it emits NO ColonelAuditEvent (CONTRACT 4 — audit is for
      # mutations only). Catalog sync stays CLI-only until this view is trusted
      # (spec: read-only drift first).
      #
      # The wire shape below is FROZEN by the frontend Zod contract
      # (src/schemas/api/internal/responses/colonel-billing.ts) — in particular
      # `source` is an enum of exactly 'stripe' | 'local_config'.
      #
      # ## Request
      #
      # GET /api/colonel/billing/catalog
      #
      # ## Response (record/details envelope)
      #
      # {
      #   record: {},
      #   details: {
      #     source: "stripe" | "local_config",
      #     stripe_configured: true,
      #     config_plans: [ <PlanEntry>, ... ],
      #     live_plans:   [ <PlanEntry>, ... ],
      #     drift: {
      #       in_sync: false,
      #       only_in_config: ["legacy_v1"],
      #       only_in_live:   ["identity_plus_v2"],
      #       changed: [ { planid: "identity_plus_v1", name: "Identity+",
      #                    fields: ["entitlements", "limits"] } ]
      #     }
      #   }
      # }
      #
      # PlanEntry = {
      #   planid:, name:, tier:, tenancy:, region:, display_order:,
      #   show_on_plans_page:, description:, entitlements: [...], limits: {...}
      # }
      #
      # ## Source Indicator
      #
      # - "stripe": live plans loaded from the Stripe-synced Redis cache
      #   (production). Drift is meaningful.
      # - "local_config": the Stripe cache is empty (dev / no Stripe). live_plans
      #   is [] and every configured plan reports as only_in_config; the UI
      #   should warn that drift cannot be evaluated.
      #
      # ## Security
      #
      # Requires colonel role. Enforced at BOTH the router (role=colonel) AND
      # here (verify_one_of_roles!(colonel: true)) — defense in depth (epic #20).
      class GetBillingCatalog < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelBillingCatalog' }.freeze

        attr_reader :result

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Billing::CatalogDrift.new.call

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              source: result.source,
              stripe_configured: result.stripe_configured,
              config_plans: result.config_plans,
              live_plans: result.live_plans,
              drift: result.drift,
            },
          }
        end
      end
    end
  end
end

# apps/api/colonel/logic/colonel/get_billing_catalog.rb
#
# frozen_string_literal: true

require_relative '../base'

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
      # Recipe note (epic #45): unlike the other Phase-3 items this needs NO op
      # extraction and NO mutating route — the read ops already exist. This is a
      # thin HTTP adapter that REUSES the incumbent Billing::Plan source
      # (CONTRACT 5). It NEVER writes, so it emits NO AdminAuditEvent
      # (CONTRACT 4 — audit is for mutations only). Catalog sync stays CLI-only
      # until this view is trusted (spec: read-only drift first).
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

        attr_reader :config_plans, :live_plans, :drift, :source

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @config_plans = load_plans_from_config
          @live_plans   = load_plans_from_stripe_cache
          @source       = @live_plans.any? ? 'stripe' : 'local_config'
          @drift        = compute_drift(@config_plans, @live_plans)

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              source: source,
              stripe_configured: live_plans.any?,
              config_plans: config_plans,
              live_plans: live_plans,
              drift: drift,
            },
          }
        end

        private

        # Configured catalog (billing.yaml). REUSES the incumbent source.
        #
        # @return [Array<Hash>] Normalized PlanEntry hashes
        def load_plans_from_config
          ::Billing::Plan.list_plans_from_config.map { |plan| normalize_config_plan(plan) }
        rescue StandardError => ex
          OT.le '[GetBillingCatalog] Error loading plans from config',
            { exception: ex, message: ex.message }
          []
        end

        # Live plans (Stripe-synced Redis cache). Mirrors GetAvailablePlans'
        # normalization so both sides share the exact same PlanEntry shape and
        # drift compares like-for-like. Uses the bounded instances lookup, not a
        # blocking KEYS scan (CONTRACT 6).
        #
        # @return [Array<Hash>] Normalized PlanEntry hashes
        def load_plans_from_stripe_cache
          ::Billing::Plan.list_plans.map do |plan|
            {
              planid: plan.plan_id,
              name: plan.name,
              tier: plan.tier,
              tenancy: plan.tenancy,
              region: plan.region,
              display_order: plan.display_order.to_i,
              show_on_plans_page: plan.show_on_plans_page.to_s == 'true',
              description: plan.respond_to?(:description) ? plan.description : nil,
              entitlements: plan.entitlements.to_a.sort,
              limits: normalize_limits(plan.limits.hgetall || {}),
            }
          end
        rescue StandardError => ex
          OT.le '[GetBillingCatalog] Error loading plans from Stripe cache',
            { exception: ex, message: ex.message }
          []
        end

        # Select the shared PlanEntry fields from a config plan hash and
        # normalize entitlements/limits so both sides are comparable.
        def normalize_config_plan(plan)
          {
            planid: plan[:planid],
            name: plan[:name],
            tier: plan[:tier],
            tenancy: plan[:tenancy],
            region: plan[:region],
            display_order: plan[:display_order].to_i,
            show_on_plans_page: plan[:show_on_plans_page] == true,
            description: plan[:description],
            entitlements: Array(plan[:entitlements]).map(&:to_s).sort,
            limits: normalize_limits(plan[:limits] || {}),
          }
        end

        # Stringify limit values so a config "0" and a cached "0" compare equal.
        def normalize_limits(limits)
          limits.each_with_object({}) do |(key, value), acc|
            acc[key.to_s] = value.to_s
          end
        end

        # Compute the config-vs-live difference, keyed by planid.
        #
        # @return [Hash] drift summary
        def compute_drift(config_plans, live_plans)
          config_by_id = config_plans.each_with_object({}) { |p, h| h[p[:planid]] = p }
          live_by_id   = live_plans.each_with_object({}) { |p, h| h[p[:planid]] = p }

          only_in_config = (config_by_id.keys - live_by_id.keys).sort
          only_in_live   = (live_by_id.keys - config_by_id.keys).sort

          changed = (config_by_id.keys & live_by_id.keys).sort.filter_map do |planid|
            fields = drifted_fields(config_by_id[planid], live_by_id[planid])
            next if fields.empty?

            {
              planid: planid,
              name: config_by_id[planid][:name] || live_by_id[planid][:name],
              fields: fields,
            }
          end

          {
            in_sync: only_in_config.empty? && only_in_live.empty? && changed.empty?,
            only_in_config: only_in_config,
            only_in_live: only_in_live,
            changed: changed,
          }
        end

        # Which comparable fields diverge between the two sides of a plan.
        # Entitlements + limits are the operationally meaningful drift; tier and
        # display metadata are reported too so a rename doesn't hide silently.
        def drifted_fields(config_plan, live_plan)
          fields = []
          fields << 'entitlements' if config_plan[:entitlements] != live_plan[:entitlements]
          fields << 'limits'       if config_plan[:limits] != live_plan[:limits]
          fields << 'tier'         if config_plan[:tier] != live_plan[:tier]
          fields << 'name'         if config_plan[:name] != live_plan[:name]
          fields
        end
      end
    end
  end
end

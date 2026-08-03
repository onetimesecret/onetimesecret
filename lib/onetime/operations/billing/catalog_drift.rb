# lib/onetime/operations/billing/catalog_drift.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Billing
      # Config-vs-live billing catalog drift — the SINGLE implementation.
      #
      # Adapters:
      #   - `GET /api/colonel/billing/catalog` (ColonelAPI::Logic::Colonel::GetBillingCatalog)
      #   - `bin/ots billing catalog drift`
      #
      # Where `Billing::Plan.list_plans` returns ONE source (the Stripe-synced
      # Redis cache) and `list_plans_from_config` returns the other (billing.yaml),
      # this op returns BOTH plus a computed difference, so an operator can see at
      # a glance which plans exist on only one side and which diverge in
      # entitlements or limits.
      #
      # READ-ONLY: it never writes and therefore emits NO ColonelAuditEvent
      # (CONTRACT 4 — audit is for mutations only).
      #
      # ## Why an op for a read
      #
      # The drift computation was previously private to the colonel logic class,
      # so `bin/ots billing catalog …` (validate / push / pull / sync) had no way
      # to show the same view without a second implementation. Sharing it here
      # keeps one normalisation — a config "0" and a cached "0" must compare
      # equal, or every plan reports as drifted.
      #
      # ## Billing-disabled deployments
      #
      # `Billing::Plan` is only defined when billing is enabled. When it is
      # absent both sides come back empty and `billing_enabled` is false, so the
      # CLI can print "billing not configured" instead of a spurious full drift.
      # `source` deliberately keeps its original two-value domain
      # ('stripe' | 'local_config') — the frontend Zod contract pins it to that
      # enum, so a third value would break the admin catalog view.
      class CatalogDrift
        # @!attribute source [r] String —
        #   'stripe' (live cache populated; drift is meaningful) or
        #   'local_config' (cache empty — every configured plan reads as
        #   only_in_config; drift cannot be evaluated).
        # @!attribute billing_enabled [r] Boolean — false when this deployment
        #   has no billing app loaded (CLI-only signal; not part of the HTTP
        #   response).
        Result = Data.define(
          :source,
          :stripe_configured,
          :billing_enabled,
          :config_plans,
          :live_plans,
          :drift,
        )

        # @return [Result]
        def call
          config_plans = load_plans_from_config
          live_plans   = load_plans_from_stripe_cache

          Result.new(
            source: live_plans.any? ? 'stripe' : 'local_config',
            stripe_configured: live_plans.any?,
            billing_enabled: billing_available?,
            config_plans: config_plans,
            live_plans: live_plans,
            drift: compute_drift(config_plans, live_plans),
          )
        end

        # @return [Boolean] false when this deployment has no billing app loaded.
        def billing_available?
          defined?(::Billing::Plan) ? true : false
        end

        private

        # Configured catalog (billing.yaml). REUSES the incumbent source.
        #
        # @return [Array<Hash>] Normalized PlanEntry hashes
        def load_plans_from_config
          return [] unless billing_available?

          ::Billing::Plan.list_plans_from_config.map { |plan| normalize_config_plan(plan) }
        rescue StandardError => ex
          OT.le '[Billing::CatalogDrift] Error loading plans from config',
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
          return [] unless billing_available?

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
          OT.le '[Billing::CatalogDrift] Error loading plans from Stripe cache',
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

# apps/web/billing/operations/apply_subscription_to_org.rb
#
# frozen_string_literal: true

require_relative '../errors'
require_relative '../metadata'
require_relative '../lib/plan_validator'
require_relative '../lib/plan_resolver'

module Billing
  module Operations
    # Result of materialize_entitlements_for_org
    #
    # @!attribute status [Symbol] One of :materialized, :skipped_no_plan,
    #   :skipped_fresh, :would_materialize, :plan_not_found
    # @!attribute planid [String, nil] Plan ID attempted
    # @!attribute entitlements_count [Integer, nil] Count of entitlements
    # @!attribute source [Symbol, nil] :cache or :config
    # @!attribute reason [String, nil] Human-readable skip/error reason
    MaterializeResult = Data.define(:status, :planid, :entitlements_count, :source, :reason) do
      def success? = status == :materialized
      def skipped? = [:skipped_no_plan, :skipped_fresh].include?(status)
    end

    # ApplySubscriptionToOrg - Shared operation for writing subscription
    # state to an Organization.
    #
    # Two codepaths set billing fields on organizations:
    # 1. Webhook owner path (update_from_stripe_subscription)
    # 2. Webhook federated path (update_federated_org)
    #
    # This operation extracts the common field-setting logic so all
    # paths produce consistent state — particularly for the
    # complimentary marker and plan resolution.
    #
    # Usage (.call for full subscription apply):
    #   # Owner path (full update with Stripe IDs, auto-save)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: true)
    #
    #   # Federated path (no Stripe IDs, caller saves after marking federated)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: false, save: false)
    #
    #   # Explicit-plan path (when the resolved price isn't in the catalog)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: true,
    #     planid_override: 'identity_plus_v1')
    #
    # Usage (.materialize_entitlements_for_org for entitlements only):
    #   # Basic: materialize org's current plan entitlements
    #   result = ApplySubscriptionToOrg.materialize_entitlements_for_org(org)
    #
    #   # CLI batch: skip orgs already up-to-date
    #   result = ApplySubscriptionToOrg.materialize_entitlements_for_org(org,
    #     skip_if_fresh: true)
    #
    #   # Dry run: preview what would happen without writing
    #   result = ApplySubscriptionToOrg.materialize_entitlements_for_org(org,
    #     dry_run: true)
    #   puts "Would apply #{result.entitlements_count} entitlements"
    #
    #   # Fail-closed: raise on missing plan (webhook path)
    #   ApplySubscriptionToOrg.materialize_entitlements_for_org(org,
    #     raise_on_miss: true)
    #
    class ApplySubscriptionToOrg
      # @param org [Onetime::Organization] Organization to update
      # @param subscription [Stripe::Subscription] Stripe subscription
      # @param owner [Boolean] Whether org owns the subscription (gets Stripe IDs)
      # @param planid_override [String, nil] Explicit plan ID, skips catalog
      #   resolution. Use when the resolved price isn't in the catalog yet.
      # @param save [Boolean] Whether to call org.save after applying fields.
      #   Set to false when the caller needs to set additional fields before
      #   saving (e.g., federation marking).
      # @return [Boolean, nil] Result of org.save, or nil when save: false
      def self.call(org, subscription, owner: true, planid_override: nil, save: true)
        new(org, subscription, owner: owner, planid_override: planid_override, save: save).call
      end

      # Apply free tier state when subscription is canceled/deleted
      #
      # Called by webhook handlers when a subscription is deleted.
      # Centralizes the cancel path so Phase 2 entitlement materialization
      # applies to cancellations automatically.
      #
      # @param org [Onetime::Organization] Organization to update
      # @param owner [Boolean] Whether org owned the subscription (clears Stripe IDs)
      # @param save [Boolean] Whether to call org.save after applying fields
      # @return [Boolean, nil] Result of org.save, or nil when save: false
      def self.apply_free_tier(org, owner: true, save: true)
        org.subscription_status     = 'canceled'
        org.planid                  = Billing::Metadata::FREE_PLAN_ID
        org.complimentary           = nil
        org.subscription_period_end = nil if owner

        if owner
          org.stripe_subscription_id = nil
        end

        # Materialize free tier entitlements
        materialize_free_tier_entitlements(org)

        org.save if save
      end

      # Materialize free tier entitlements to org
      #
      # @param org [Onetime::Organization] Organization to update
      def self.materialize_free_tier_entitlements(org)
        config_plan = Billing::Plan.load_from_config(Billing::Metadata::FREE_PLAN_ID)
        if config_plan
          org.materialize_entitlements_from_config(config_plan)
          Onetime.ents_logger.info 'Materialized free tier entitlements',
            org_extid: org.extid,
            planid: Billing::Metadata::FREE_PLAN_ID,
            entitlements_count: org.materialized_entitlements.size

          # ADR-012 Stage 3: Re-materialize all memberships after downgrade to free tier.
          begin
            membership_result = org.rematerialize_all_memberships!
            Onetime.ents_logger.info 'Re-materialized membership entitlements (free tier)',
              org_extid: org.extid,
              success: membership_result[:success],
              failed: membership_result[:failed],
              total: membership_result[:total]

            # Cross-path consistency with MaterializePlans#handle_cascade_partial:
            # surface a partial cascade as :error so operators learn about drifted
            # memberships at detection time. Observability only — do NOT propagate
            # failure: the webhook returns 200 and the downgrade already applied;
            # a non-200 would make Stripe re-process an already-applied change.
            if membership_result[:failed].to_i.positive?
              Onetime.ents_logger.error 'Membership re-materialization had failures (free tier)',
                org_extid: org.extid,
                planid: Billing::Metadata::FREE_PLAN_ID,
                memberships_total: membership_result[:total],
                memberships_failed: membership_result[:failed],
                memberships_failed_ids: membership_result[:failed_ids]
            end
          rescue StandardError => ex
            Onetime.ents_logger.error 'Membership re-materialization failed (free tier)',
              exception: ex,
              org_extid: org.extid
          end
        else
          Onetime.ents_logger.warn 'Free plan not in config, cannot materialize',
            org_extid: org.extid,
            planid: Billing::Metadata::FREE_PLAN_ID
        end
      end

      # Materialize entitlements for org's current planid
      #
      # Used by federation claim path and other codepaths that set planid
      # without going through the full ApplySubscriptionToOrg.call flow.
      #
      # @param org [Onetime::Organization] Organization with planid already set
      # @param raise_on_miss [Boolean] Whether to raise PlanCacheMissError (default: false)
      # @param skip_if_fresh [Boolean] Skip if already materialized and not stale (default: false)
      # @param dry_run [Boolean] Return result without materializing (default: false)
      # @return [MaterializeResult] Result with status, counts, and metadata
      def self.materialize_entitlements_for_org(org, raise_on_miss: false, skip_if_fresh: false, dry_run: false)
        planid = org.planid.to_s
        return skipped_no_plan_result if planid.empty?

        plan, source = load_plan_for_materialize(planid)
        return plan_not_found_result(org, planid, raise_on_miss) unless plan

        return skipped_fresh_result(org, planid, source) if skip_if_fresh && entitlements_fresh?(org, plan)
        return would_materialize_result(planid, plan, source) if dry_run

        execute_materialize(org, plan, source)
      end

      # Check if org's entitlements are already materialized and current
      def self.entitlements_fresh?(org, plan)
        org.entitlements_materialized? && !org.entitlements_stale?(plan)
      end
      private_class_method :entitlements_fresh?

      # Load plan from cache or config
      #
      # @param planid [String] Plan ID to load
      # @return [Array(Object, Symbol), Array(nil, nil)] [plan, :cache/:config] or [nil, nil]
      def self.load_plan_for_materialize(planid)
        plan = Billing::Plan.load(planid)
        return [plan, :cache] if plan

        config_plan = Billing::Plan.load_from_config(planid)
        return [config_plan, :config] if config_plan

        [nil, nil]
      end
      private_class_method :load_plan_for_materialize

      # Execute materialization and return result
      def self.execute_materialize(org, plan, source)
        planid = org.planid.to_s

        if source == :cache
          org.materialize_entitlements_from_plan(plan)
        else
          org.materialize_entitlements_from_config(plan)
        end

        count = org.materialized_entitlements.size
        Onetime.ents_logger.info 'Materialized entitlements for org',
          org_extid: org.extid,
          planid: planid,
          entitlements_count: count,
          source: source.to_s

        # ADR-012 Stage 3: Re-materialize all memberships after org plan change.
        # Each membership's effective entitlements are org.entitlements ∩ ROLE_ENTITLEMENTS[role].
        # This propagates the new plan's entitlements to all active members.
        begin
          membership_result = org.rematerialize_all_memberships!
          Onetime.ents_logger.info 'Re-materialized membership entitlements',
            org_extid: org.extid,
            planid: planid,
            success: membership_result[:success],
            failed: membership_result[:failed],
            total: membership_result[:total]

          # Cross-path consistency with MaterializePlans#handle_cascade_partial:
          # surface a partial cascade as :error so operators learn about drifted
          # memberships at detection time. Observability only — do NOT propagate
          # failure: the webhook returns 200 and the plan change already applied;
          # a non-200 would make Stripe re-process an already-applied change.
          if membership_result[:failed].to_i.positive?
            Onetime.ents_logger.error 'Membership re-materialization had failures',
              org_extid: org.extid,
              planid: planid,
              memberships_total: membership_result[:total],
              memberships_failed: membership_result[:failed],
              memberships_failed_ids: membership_result[:failed_ids]
          end
        rescue StandardError => ex
          # Membership re-materialization is degradable — the fallback path in
          # membership.entitlements computes on-the-fly. Log and continue.
          Onetime.ents_logger.error 'Membership re-materialization failed',
            exception: ex,
            org_extid: org.extid
        end

        MaterializeResult.new(
          status: :materialized,
          planid: planid,
          entitlements_count: count,
          source: source,
          reason: nil,
        )
      end
      private_class_method :execute_materialize

      # Result builders
      def self.skipped_no_plan_result
        MaterializeResult.new(
          status: :skipped_no_plan,
          planid: nil,
          entitlements_count: nil,
          source: nil,
          reason: 'Organization has no planid',
        )
      end
      private_class_method :skipped_no_plan_result

      def self.plan_not_found_result(org, planid, raise_on_miss)
        raise_plan_not_found(org, planid) if raise_on_miss
        build_plan_not_found_result(org, planid)
      end
      private_class_method :plan_not_found_result

      def self.raise_plan_not_found(org, planid)
        raise Billing::PlanCacheMissError.new(
          'Cannot materialize entitlements - plan not found',
          plan_id: planid,
          context: 'ApplySubscriptionToOrg.materialize_entitlements_for_org',
          organization_id: org.extid,
        )
      end
      private_class_method :raise_plan_not_found

      def self.build_plan_not_found_result(org, planid)
        Onetime.ents_logger.warn 'Plan not found, cannot materialize',
          org_extid: org.extid,
          planid: planid

        MaterializeResult.new(
          status: :plan_not_found,
          planid: planid,
          entitlements_count: nil,
          source: nil,
          reason: "Plan '#{planid}' not in cache or config",
        )
      end
      private_class_method :build_plan_not_found_result

      def self.skipped_fresh_result(org, planid, source)
        MaterializeResult.new(
          status: :skipped_fresh,
          planid: planid,
          entitlements_count: org.materialized_entitlements.size,
          source: source,
          reason: 'Entitlements already materialized and not stale',
        )
      end
      private_class_method :skipped_fresh_result

      def self.would_materialize_result(planid, plan, source)
        MaterializeResult.new(
          status: :would_materialize,
          planid: planid,
          entitlements_count: entitlements_count_for(plan, source),
          source: source,
          reason: nil,
        )
      end
      private_class_method :would_materialize_result

      def self.entitlements_count_for(plan, source)
        source == :cache ? plan.entitlements.size : (plan[:entitlements] || []).size
      end
      private_class_method :entitlements_count_for

      def initialize(org, subscription, owner: true, planid_override: nil, save: true)
        @org              = org
        @subscription     = subscription
        @owner            = owner
        @planid_override  = planid_override
        @save             = save
      end

      def call
        apply_status_fields
        apply_plan_id
        apply_complimentary_marker
        apply_owner_fields if @owner
        materialize_entitlements

        @org.save if @save
      end

      private

      # Fields common to both owner and federated orgs
      def apply_status_fields
        @org.subscription_status = @subscription.status

        period_end                   = @subscription.items.data.first&.current_period_end
        @org.subscription_period_end = period_end.to_s if period_end
      end

      # Resolve plan from catalog (owner) or metadata (federated)
      #
      # Owner orgs use catalog-first resolution (fail-closed) because the
      # price_id is from the local Stripe account and must exist in catalog.
      #
      # Federated orgs use metadata-first resolution because cross-region
      # price IDs won't exist in the local catalog. The universal plan name
      # (e.g., 'identity_plus_v1') is stored in Stripe metadata.
      #
      def apply_plan_id
        if @planid_override
          @org.planid = @planid_override
          return
        end

        plan_id = if @owner
                    # Owner path: catalog lookup (fail-closed on miss)
                    price    = @subscription.items.data.first&.price
                    price_id = price&.id
                    return unless price_id

                    Billing::PlanValidator.resolve_plan_id(price_id)
                  else
                    # Federated path: read canonical plan_id directly from metadata
                    # Cross-region price IDs aren't in the local catalog, so we can't
                    # use catalog lookup. Metadata contains the canonical family ID.
                    federated_plan_id(@subscription.metadata[Billing::Metadata::FIELD_PLAN_ID])
                  end

        @org.planid = plan_id if plan_id
      end

      # Validate and return the federated plan_id from subscription metadata.
      #
      # The federated path cannot catalog-validate (cross-region price IDs
      # aren't in the local catalog), but the stored value is the universal
      # canonical family ID (e.g., 'identity_plus_v1'). We validate its
      # *shape* against PlanResolver::CANONICAL_PLAN_ID_PATTERN — this rejects
      # typos, interval-suffixed IDs, and uppercase without requiring local
      # catalog membership (which would break federation by design).
      #
      # Fail-closed: a malformed value raises rather than corrupting
      # org.planid, mirroring the owner path's CatalogMissError behavior.
      #
      # @param raw [String, nil] plan_id from subscription metadata
      # @return [String, nil] the validated plan_id, or nil if metadata absent
      # @raise [Billing::InvalidPlanMetadataError] If the value is malformed
      def federated_plan_id(raw)
        # Absent metadata is not an error here: @org.planid is left unchanged
        # (the `if plan_id` guard in apply_plan_id), preserving prior state.
        plan_id = raw.to_s.strip
        return nil if plan_id.empty?

        return plan_id if Billing::PlanResolver.canonical_plan_id?(plan_id)

        raise Billing::InvalidPlanMetadataError.new(
          plan_id: plan_id,
          context: 'ApplySubscriptionToOrg#apply_plan_id (federated)',
        )
      end

      # Cache Stripe's complimentary marker locally (Stripe → org, never reverse)
      #
      # Reads metadata['complimentary'] from the Stripe subscription and
      # stores it on the org for fast local queries. This is the only
      # codepath that should write org.complimentary.
      def apply_complimentary_marker
        meta               = @subscription.metadata
        @org.complimentary = if meta && meta[Billing::Metadata::FIELD_COMPLIMENTARY].to_s == 'true'
                               'true'
                             end
      end

      # Fields only set on owner orgs (not federated)
      def apply_owner_fields
        @org.stripe_subscription_id = @subscription.id
        @org.stripe_customer_id     = @subscription.customer
      end

      # Materialize entitlements from resolved plan to org-local storage
      #
      # Loads the plan from cache/config and copies entitlements + limits
      # to org fields. This moves entitlement resolution from read time
      # to write time (webhook time).
      #
      # Delegates to class method with raise_on_miss: true.
      # PlanCacheMissError raised here is correct behavior - webhook
      # handlers retry, and it's visible in observability.
      def materialize_entitlements
        self.class.materialize_entitlements_for_org(@org, raise_on_miss: true)
      end
    end
  end
end

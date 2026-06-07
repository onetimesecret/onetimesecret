# apps/web/billing/lib/billing_service.rb
#
# frozen_string_literal: true

require_relative '../metadata'
require_relative '../models/plan'

module Billing
  # BillingService - Centralized billing logic
  #
  # Provides reusable methods for:
  # - Plan ID resolution from Stripe subscriptions
  # - Sync health computation for organizations
  # - Billing state comparison between local and Stripe data
  # - Plan validation against the catalog
  #
  # This module consolidates billing logic previously scattered across:
  # - ColonelAPI::Logic::Colonel::ListOrganizations
  # - ColonelAPI::Logic::Colonel::InvestigateOrganization
  # - Onetime::Models::Features::WithOrganizationBilling
  #
  module BillingService
    extend self

    # =========================================================================
    # Plan ID Resolution
    # =========================================================================

    # Resolve plan_id from a Stripe subscription using catalog-first approach
    #
    # Priority order:
    # 1. Catalog lookup by price_id (most authoritative - prices are immutable)
    # 2. Price-level metadata['plan_id']
    # 3. Subscription-level metadata['plan_id'] (may be stale)
    #
    # @param subscription [Stripe::Subscription] Stripe subscription object
    # @return [String, nil] Resolved plan ID or nil if unresolvable
    def resolve_plan_id_from_subscription(subscription)
      price    = subscription.items.data.first&.price
      price_id = price&.id

      # 1. Try catalog lookup first (most authoritative)
      if price_id
        plan = ::Billing::Plan.find_by_stripe_price_id(price_id)
        if plan
          OT.info '[BillingService.resolve_plan_id_from_subscription] Resolved via catalog',
            {
              plan_id: plan.plan_id,
              price_id: price_id,
              subscription_id: subscription.id,
            }
          return plan.plan_id
        end
      end

      # 2. Try price-level metadata
      price_plan_id = price&.metadata&.[](Metadata::FIELD_PLAN_ID)
      if price_plan_id && !price_plan_id.empty?
        OT.info '[BillingService.resolve_plan_id_from_subscription] Resolved via price metadata',
          {
            plan_id: price_plan_id,
            price_id: price_id,
            subscription_id: subscription.id,
          }
        return price_plan_id
      end

      # 3. Try subscription-level metadata (fallback, may be stale)
      sub_plan_id = subscription.metadata&.[](Metadata::FIELD_PLAN_ID)
      if sub_plan_id && !sub_plan_id.empty?
        OT.lw '[BillingService.resolve_plan_id_from_subscription] Using subscription metadata (may be stale)',
          {
            plan_id: sub_plan_id,
            price_id: price_id,
            subscription_id: subscription.id,
          }
        return sub_plan_id
      end

      OT.lw '[BillingService.resolve_plan_id_from_subscription] Unable to resolve plan_id',
        {
          price_id: price_id,
          subscription_id: subscription.id,
        }
      nil
    end

    # Validate that a plan_id exists in the catalog
    #
    # @param plan_id [String] Plan ID to validate
    # @return [Boolean] True if plan exists in catalog
    def valid_plan_id?(plan_id)
      return false if plan_id.to_s.empty?

      # Check if it's a known free plan
      return true if Metadata::FREE_PLAN_IDS.include?(plan_id)

      # Check catalog cache
      plan = ::Billing::Plan.load(plan_id)
      return true if plan&.exists?

      # Check static config as fallback
      config_plans = Onetime.conf.dig(:billing, :plans) || {}
      config_plans.key?(plan_id.to_sym)
    end

    # =========================================================================
    # Sync Health Computation
    # =========================================================================

    # Compute sync health status based on billing state consistency
    #
    # Sync status values:
    #   synced - Consistent state (active sub + paid plan, OR no sub + free plan)
    #   potentially_stale - Inconsistent state requiring investigation
    #   unknown - Cannot determine (no billing data yet)
    #
    # @param org [Onetime::Organization] Organization to check
    # @return [String] 'synced', 'potentially_stale', or 'unknown'
    def compute_sync_status(org)
      planid              = org.planid.to_s
      subscription_id     = org.stripe_subscription_id.to_s
      subscription_status = org.subscription_status.to_s

      # No billing data yet -> unknown
      return 'unknown' if planid.empty? && subscription_id.empty?

      has_active_subscription = %w[active trialing].include?(subscription_status)
      has_paid_plan           = !planid.empty? && !Metadata::FREE_PLAN_IDS.include?(planid)
      has_free_plan           = planid.empty? || Metadata::FREE_PLAN_IDS.include?(planid)

      # Consistent states
      return 'synced' if has_active_subscription && has_paid_plan
      return 'synced' if !has_active_subscription && has_free_plan && subscription_id.empty?
      return 'synced' if subscription_status == 'canceled' && has_free_plan
      return 'synced' if subscription_status == 'past_due' && has_paid_plan

      # Inconsistent states
      if has_active_subscription && has_free_plan
        return 'potentially_stale'
      end

      if !has_active_subscription && has_paid_plan && subscription_status != 'past_due'
        return 'potentially_stale'
      end

      # Default to unknown for edge cases
      'unknown'
    end

    # Provide human-readable reason for sync status
    #
    # @param org [Onetime::Organization] Organization to check
    # @return [String, nil] Reason for the sync status or nil if synced
    def compute_sync_status_reason(org)
      planid              = org.planid.to_s
      subscription_status = org.subscription_status.to_s

      has_active_subscription = %w[active trialing].include?(subscription_status)
      has_paid_plan           = !planid.empty? && !Metadata::FREE_PLAN_IDS.include?(planid)
      has_free_plan           = planid.empty? || Metadata::FREE_PLAN_IDS.include?(planid)

      if has_active_subscription && has_free_plan
        return 'Active subscription but planid is free - possible missed webhook'
      end

      if !has_active_subscription && has_paid_plan && subscription_status != 'past_due'
        return 'Paid plan but no active subscription - may need downgrade'
      end

      nil
    end

    # =========================================================================
    # Billing State Comparison
    # =========================================================================

    # Compare local billing state with Stripe subscription data
    #
    # @param local [Hash] Local organization billing state
    # @param stripe [Hash] Stripe subscription state
    # @return [Hash] Comparison result with :match, :verdict, :issues
    def compare_billing_states(local, stripe)
      unless stripe[:available]
        return {
          match: nil,
          verdict: 'unable_to_compare',
          details: stripe[:reason],
        }
      end

      sub           = stripe[:subscription]
      local_planid  = local[:planid].to_s
      stripe_planid = sub[:resolved_plan_id].to_s
      local_status  = local[:subscription_status].to_s
      stripe_status = sub[:status].to_s

      issues = []

      # Check plan ID match (family-keyed IDs, direct string comparison)
      unless local_planid == stripe_planid
        issues << {
          field: 'planid',
          local: local_planid.empty? ? '(empty)' : local_planid,
          stripe: stripe_planid.empty? ? '(unresolvable)' : stripe_planid,
          severity: 'high',
        }
      end

      # Check subscription status match
      if local_status != stripe_status
        issues << {
          field: 'subscription_status',
          local: local_status.empty? ? '(empty)' : local_status,
          stripe: stripe_status,
          severity: 'medium',
        }
      end

      # Check subscription ID match
      if local[:stripe_subscription_id] != sub[:id]
        issues << {
          field: 'stripe_subscription_id',
          local: local[:stripe_subscription_id],
          stripe: sub[:id],
          severity: 'critical',
        }
      end

      {
        match: issues.empty?,
        verdict: issues.empty? ? 'synced' : 'mismatch_detected',
        issues: issues,
      }
    end

    # =========================================================================
    # Helper Methods
    # =========================================================================

    # Check if a plan ID represents a free tier
    #
    # @param planid [String] Plan ID to check
    # @return [Boolean] True if this is a free plan
    def free_plan?(planid)
      planid.to_s.empty? || Metadata::FREE_PLAN_IDS.include?(planid.to_s)
    end

    # Check if a plan ID represents a paid tier
    #
    # @param planid [String] Plan ID to check
    # @return [Boolean] True if this is a paid plan
    def paid_plan?(planid)
      !free_plan?(planid)
    end

    # Check if subscription status indicates an active subscription
    #
    # @param status [String] Subscription status
    # @return [Boolean] True if active or trialing
    def active_subscription_status?(status)
      %w[active trialing].include?(status.to_s)
    end
  end
end

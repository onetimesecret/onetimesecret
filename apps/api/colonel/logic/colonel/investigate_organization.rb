# apps/api/colonel/logic/colonel/investigate_organization.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Investigates an organization's billing state by comparing local data
      # against the actual Stripe subscription.
      #
      # This allows admins to verify sync health on-demand for any organization,
      # regardless of the computed sync_status.
      #
      class InvestigateOrganization < ColonelAPI::Logic::Base
        attr_reader :org, :investigation_result

        def process_params
          @org_id = params['org_id']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID required') if @org_id.to_s.empty?

          @org = load_organization
          raise_form_error('Organization not found') unless @org
        end

        def process
          @investigation_result = investigate_billing_state

          success_data
        end

        private

        def load_organization
          # Try loading by extid first (the URL-friendly identifier)
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          # Fall back to objid
          Onetime::Organization.load(@org_id)
        end

        def investigate_billing_state
          local_state = build_local_state
          stripe_state = fetch_stripe_state

          {
            org_id: org.objid,
            extid: org.extid,
            investigated_at: Time.now.utc.strftime('%Y-%m-%d %H:%M:%S UTC'),
            local: local_state,
            stripe: stripe_state,
            comparison: compare_states(local_state, stripe_state),
          }
        end

        def build_local_state
          {
            planid: org.planid,
            stripe_customer_id: org.stripe_customer_id,
            stripe_subscription_id: org.stripe_subscription_id,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end,
          }
        end

        def fetch_stripe_state
          subscription_id = org.stripe_subscription_id.to_s

          # No subscription ID stored locally
          if subscription_id.empty?
            return {
              available: false,
              reason: 'No subscription ID stored locally',
              subscription: nil,
            }
          end

          # Fetch from Stripe
          begin
            subscription = Stripe::Subscription.retrieve(
              id: subscription_id,
              expand: ['items.data.price.product'],
            )

            {
              available: true,
              reason: nil,
              subscription: extract_subscription_data(subscription),
            }
          rescue Stripe::InvalidRequestError => e
            {
              available: false,
              reason: "Stripe error: #{e.message}",
              subscription: nil,
            }
          rescue Stripe::StripeError => e
            {
              available: false,
              reason: "Stripe API error: #{e.message}",
              subscription: nil,
            }
          end
        end

        def extract_subscription_data(subscription)
          item = subscription.items.data.first
          price = item&.price
          product = price&.product

          # Try to resolve plan_id from various sources
          resolved_plan_id = resolve_plan_id(subscription, price, product)

          {
            id: subscription.id,
            status: subscription.status,
            current_period_end: item&.current_period_end,
            price_id: price&.id,
            price_nickname: price&.nickname,
            product_id: product.is_a?(Stripe::Product) ? product.id : product,
            product_name: product.is_a?(Stripe::Product) ? product.name : nil,
            # Plan ID resolution
            subscription_metadata_plan_id: subscription.metadata&.[]('plan_id'),
            price_metadata_plan_id: price&.metadata&.[]('plan_id'),
            resolved_plan_id: resolved_plan_id,
          }
        end

        # Check if two plan IDs match, accounting for interval suffix only
        #
        # Plan IDs may differ only by billing interval suffix:
        # - "identity_plus_v1" vs "identity_plus_v1_monthly"
        #
        # This method normalizes by stripping interval suffix and compares.
        # Does NOT do prefix matching - "identity_plus" is NOT considered
        # to match "identity_plus_v1" since they are different plans.
        #
        # @param local_planid [String] Plan ID stored locally on organization
        # @param stripe_planid [String] Plan ID resolved from Stripe subscription
        # @return [Boolean] True if plans match (same base identity)
        def plans_match?(local_planid, stripe_planid)
          return true if local_planid == stripe_planid
          return false if local_planid.empty? || stripe_planid.empty?

          # Normalize both by stripping interval suffix only
          local_base = normalize_plan_id(local_planid)
          stripe_base = normalize_plan_id(stripe_planid)

          return true if local_base == stripe_base

          # Try looking up the plan_code from cache for accurate comparison
          # plan_code groups monthly/yearly variants (e.g., plan_code="identity_plus" for identity_plus_v1_monthly)
          stripe_plan = ::Billing::Plan.load(stripe_planid)
          if stripe_plan&.plan_code
            # Compare local with the Stripe plan's plan_code
            return true if local_planid == stripe_plan.plan_code
            return true if local_base == stripe_plan.plan_code
          end

          false
        end

        # Normalize a plan ID by stripping interval suffix
        #
        # @param planid [String] Plan ID to normalize
        # @return [String] Normalized plan ID without interval suffix
        def normalize_plan_id(planid)
          planid.to_s.sub(/_(month|year)ly$/, '')
        end

        # Resolve plan_id using the same logic as the webhook handler
        def resolve_plan_id(subscription, price, _product)
          # 1. Try subscription-level metadata
          plan_id = subscription.metadata&.[]('plan_id')
          return plan_id if plan_id && !plan_id.empty?

          # 2. Try price-level metadata
          plan_id = price&.metadata&.[]('plan_id')
          return plan_id if plan_id && !plan_id.empty?

          # 3. Try plan catalog lookup by price_id
          if price&.id
            plan = ::Billing::Plan.find_by_stripe_price_id(price.id)
            return plan.plan_id if plan
          end

          nil
        end

        def compare_states(local, stripe)
          unless stripe[:available]
            return {
              match: nil,
              verdict: 'unable_to_compare',
              details: stripe[:reason],
            }
          end

          sub = stripe[:subscription]
          local_planid = local[:planid].to_s
          stripe_planid = sub[:resolved_plan_id].to_s
          local_status = local[:subscription_status].to_s
          stripe_status = sub[:status].to_s

          issues = []

          # Check plan ID match using normalized comparison
          # Plan IDs may differ by interval suffix (e.g., "identity_plus" vs "identity_plus_v1_monthly")
          # We compare the base plan identity, not the billing interval
          unless plans_match?(local_planid, stripe_planid)
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

          # Check subscription ID match (should always match, but verify)
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

        def success_data
          {
            record: investigation_result,
            details: {},
          }
        end
      end
    end
  end
end

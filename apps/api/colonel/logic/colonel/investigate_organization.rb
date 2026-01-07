# apps/api/colonel/logic/colonel/investigate_organization.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'

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
          local_state  = build_local_state
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
          rescue Stripe::InvalidRequestError => ex
            {
              available: false,
              reason: "Stripe error: #{ex.message}",
              subscription: nil,
            }
          rescue Stripe::StripeError => ex
            {
              available: false,
              reason: "Stripe API error: #{ex.message}",
              subscription: nil,
            }
          end
        end

        def extract_subscription_data(subscription)
          item    = subscription.items.data.first
          price   = item&.price
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

        # Check if two plan IDs match, accounting for interval suffix
        #
        # @param local_planid [String] Plan ID stored locally on organization
        # @param stripe_planid [String] Plan ID resolved from Stripe subscription
        # @return [Boolean] True if plans match (same base identity)
        # @see Billing::BillingService.plans_match?
        def plans_match?(local_planid, stripe_planid)
          Billing::BillingService.plans_match?(local_planid, stripe_planid)
        end

        # Normalize a plan ID by stripping interval suffix
        #
        # @param planid [String] Plan ID to normalize
        # @return [String] Normalized plan ID without interval suffix
        # @see Billing::BillingService.normalize_plan_id
        def normalize_plan_id(planid)
          Billing::BillingService.normalize_plan_id(planid)
        end

        # Resolve plan_id using catalog-first approach
        #
        # @see Billing::BillingService.resolve_plan_id_from_subscription
        def resolve_plan_id(subscription, _price, _product)
          # Use the centralized resolver for catalog-first resolution
          Billing::BillingService.resolve_plan_id_from_subscription(subscription)
        end

        # Compare local and Stripe billing states
        #
        # @param local [Hash] Local organization billing state
        # @param stripe [Hash] Stripe subscription state
        # @return [Hash] Comparison result
        # @see Billing::BillingService.compare_billing_states
        def compare_states(local, stripe)
          Billing::BillingService.compare_billing_states(local, stripe)
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

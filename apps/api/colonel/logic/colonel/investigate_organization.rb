# apps/api/colonel/logic/colonel/investigate_organization.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'

module ColonelAPI
  module Logic
    module Colonel
      # Investigate Organization
      #
      # @api Investigates an organization's billing state by comparing local
      #   data against the actual Stripe subscription. Returns both local and
      #   Stripe-side state along with a comparison indicating whether they
      #   are in sync. Requires colonel role.
      #
      # This allows admins to verify sync health on-demand for any organization,
      # regardless of the computed sync_status.
      #
      # ## Audited (#4336)
      #
      # This route READS rather than mutates, and CONTRACT 4 does not ask reads
      # to audit — but it is audited anyway, on the narrower ground that it
      # reaches OUT of this system on the operator's behalf: it pulls a named
      # customer's live subscription state from Stripe. That is a disclosure of
      # a customer's billing posture to whoever asked, and without an event
      # there is no record of who asked. The two other colonel routes that touch
      # a customer's billing state (entitlement override, plan set) mutate and
      # were already audited; this one was the gap.
      #
      # `detail` records WHAT WAS COMPARED, never the material compared with:
      # the verdict, whether Stripe answered, and how many fields diverged. No
      # Stripe customer/subscription/price ids, no API keys, no plan payloads —
      # those stay in the response body, which is a colonel-only surface with
      # its own shape.
      class InvestigateOrganization < ColonelAPI::Logic::Base
        include Onetime::AuditedFailure

        SCHEMAS = { response: 'investigateOrganization' }.freeze

        AUDIT_VERB = 'organization.investigate'

        # Failure auditing (Onetime::AuditedFailure), matching the DeleteSecret /
        # SetEntitlementPreview precedent for colonel logic that records inline.
        # Wraps #process, which Otto runs AFTER #raise_concerns — so the
        # colonel-role check and the not-found lookup that live there are
        # structurally outside the audited region, and an authorization
        # rejection can never write an event. A Stripe transport failure that
        # escapes the per-error rescues in #fetch_stripe_state does.
        # `actor` is explicit: the ops' `@actor` default does not exist on a
        # Logic class.
        audit_failures :process,
          verb: AUDIT_VERB,
          target: -> { org&.extid },
          actor: -> { cust&.extid }

        attr_reader :org, :investigation_result

        def process_params
          @org_id = sanitize_identifier(params['org_id'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID required') if @org_id.to_s.empty?

          @org = load_organization
          raise_form_error('Organization not found') unless @org
        end

        def process
          @investigation_result = investigate_billing_state

          record_audit_event

          success_data
        end

        private

        # One event per investigation. NOT fail-closed: nothing was destroyed,
        # so trading a working investigation for a hard failure buys nothing —
        # the same reasoning the model's fail-closed note gives for the
        # additive/corrective family.
        def record_audit_event
          comparison = investigation_result[:comparison] || {}

          Onetime::ColonelAuditEvent.record(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: org&.extid,
            result: :success,
            detail: {
              verdict: comparison[:verdict],
              stripe_available: investigation_result.dig(:stripe, :available),
              issue_count: comparison[:issues]&.size || 0,
            },
          )
        end

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

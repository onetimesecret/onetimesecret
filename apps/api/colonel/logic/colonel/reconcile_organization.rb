# apps/api/colonel/logic/colonel/reconcile_organization.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/operations/apply_subscription_to_org'

module ColonelAPI
  module Logic
    module Colonel
      # Reconcile Organization (Colonel)
      #
      # The remediation counterpart to InvestigateOrganization. Investigate is
      # read-only — it surfaces a local↔Stripe mismatch but offers no fix. This
      # writes the authoritative state back:
      #
      # - With a Stripe subscription: re-pull the live subscription and apply it
      #   (planid, subscription_status, period_end, Stripe ids, then
      #   re-materialize entitlements + memberships) via the same
      #   {Billing::Operations::ApplySubscriptionToOrg} path the webhook uses, so
      #   an operator-triggered reconcile and a webhook converge on identical
      #   state.
      # - Without a Stripe subscription: re-materialize entitlements from the
      #   org's current plan. This has no Stripe billing to sync, but it clears
      #   entitlement drift (e.g. an orphaned entry left in `materialized`).
      #
      # MUTATING + guarded (typed confirmation client-side) + audited
      # server-side, mirroring ManageEntitlementOverride.
      #
      class ReconcileOrganization < ColonelAPI::Logic::Base
        attr_reader :org, :outcome, :before_state, :after_state

        def process_params
          @org_id = sanitize_identifier(params['org_id'])
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?
        end

        def process
          @before_state = snapshot_state
          @outcome      = reconcile!
          # Reload so the after-snapshot reflects the freshly-written fields.
          @org          = load_organization
          @after_state  = snapshot_state

          record_audit_event

          success_data
        end

        private

        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        def reconcile!
          subscription_id = org.stripe_subscription_id.to_s
          return reconcile_entitlements_only if subscription_id.empty?

          reconcile_from_stripe(subscription_id)
        rescue Stripe::StripeError => ex
          raise_form_error("Stripe error: #{ex.message}")
        end

        def reconcile_from_stripe(subscription_id)
          subscription = Stripe::Subscription.retrieve(
            id: subscription_id,
            expand: ['items.data.price.product'],
          )
          Billing::Operations::ApplySubscriptionToOrg.call(org, subscription, owner: true)

          { mode: 'stripe_sync', status: 'applied', reason: nil }
        end

        def reconcile_entitlements_only
          result = Billing::Operations::ApplySubscriptionToOrg
            .materialize_entitlements_for_org(org)

          {
            mode: 'entitlements_only',
            status: result.status.to_s,
            reason: result.reason,
          }
        end

        def snapshot_state
          {
            planid: org.planid,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end,
            materialized_count: org.materialized_entitlements.size,
          }
        end

        # One audit event per reconcile (CONTRACT 4 / epic D4). actor/target are
        # PUBLIC ids; the before/after billing diff is captured in detail so the
        # trail records what the reconcile actually changed.
        def record_audit_event
          Onetime::AdminAuditEvent.record(
            actor: cust.extid,
            verb: 'organization.reconcile',
            target: org.extid,
            result: :success,
            detail: {
              mode: outcome[:mode],
              status: outcome[:status],
              before: before_state,
              after: after_state,
            },
          )
        end

        def success_data
          {
            record: {
              org_id: org.objid,
              extid: org.extid,
              mode: outcome[:mode],
              status: outcome[:status],
              reason: outcome[:reason],
              before: before_state,
              after: after_state,
            },
          }
        end
      end
    end
  end
end

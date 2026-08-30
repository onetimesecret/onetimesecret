# apps/api/colonel/logic/colonel/update_organization_plan.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative '../../../../../apps/web/billing/lib/billing_service'
require 'onetime/operations/org/set_plan'

module ColonelAPI
  module Logic
    module Colonel
      # Update Organization Plan (Colonel) — THIN ADAPTER.
      #
      # Changes an organization's plan with catalog validation. This is the
      # org-level successor to UpdateUserPlan: the billing relationship lives
      # on Organization (Stripe ids, subscription state and the entitlement
      # engine all key off the org), so the admin plan control operates here.
      # UpdateUserPlan writes the deprecated Customer#planid and remains only
      # for the legacy no-org accounts.
      #
      # All behaviour (the planid write, entitlement re-materialization from
      # the new plan, the SINGLE admin audit event) lives in
      # {Onetime::Operations::Org::SetPlan}. This class owns only HTTP
      # concerns: params, authorization, catalog validation, response shape.
      #
      # DO NOT re-add an audit event here. The op emits exactly one.
      #
      # A change on a Stripe-linked org is allowed (it is the escape hatch for
      # stale-planid repairs) but flagged in `details.warning`: the next
      # webhook/reconcile re-derives planid from the live subscription and may
      # overwrite it.
      class UpdateOrganizationPlan < ColonelAPI::Logic::Base
        attr_reader :org, :new_planid, :old_planid, :result

        def process_params
          @org_id     = sanitize_identifier(params['org_id'])
          @new_planid = sanitize_identifier(params['planid'])

          raise_form_error('Organization ID is required', field: :org_id) if @org_id.to_s.empty?
          raise_form_error('Plan ID is required', field: :planid) if new_planid.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @org = load_organization
          raise_not_found('Organization not found') unless @org&.exists?

          # Validate plan_id exists in catalog (mirrors UpdateUserPlan).
          return if Billing::BillingService.valid_plan_id?(new_planid)

          raise_form_error(
            "Invalid plan ID '#{new_planid}'. Plan must exist in billing catalog or config.",
            field: :planid,
          )
        end

        def process
          @old_planid = org.planid

          @result = Onetime::Operations::Org::SetPlan.new(
            org: org,
            planid: new_planid,
            actor: cust.extid, # acting colonel's PUBLIC id (never an objid)
          ).call

          success_data
        end

        def success_data
          message = if result.status == :success
            'Organization plan updated successfully'
          else
            'Organization already on this plan'
          end

          {
            record: {
              org_id: org.objid,
              extid: org.extid,
              display_name: org.display_name,
              old_planid: old_planid,
              new_planid: org.planid,
              updated: org.updated&.to_i,
            },
            details: {
              changed: result.status == :success,
              # The engine status (:materialized, :skipped_standalone,
              # :materialization_failed, ...) as a string; null on a no-op.
              materialization: result.materialization&.to_s,
              message: message,
              warning: stripe_overwrite_warning,
            },
          }
        end

        private

        # Resolve by PUBLIC id (extid) first — every admin surface routes by
        # extid — then fall back to objid. Mirrors GetOrganizationDetail.
        def load_organization
          org = Onetime::Organization.find_by_extid(@org_id)
          return org if org

          Onetime::Organization.load(@org_id)
        end

        # @return [String, nil]
        def stripe_overwrite_warning
          return nil if org.stripe_subscription_id.to_s.empty?
          return nil if result.status != :success

          'This organization has a live Stripe subscription; the next webhook ' \
            'or reconcile re-derives the plan from Stripe and may overwrite ' \
            'this change. Change the subscription in Stripe to make it stick.'
        end
      end
    end
  end
end

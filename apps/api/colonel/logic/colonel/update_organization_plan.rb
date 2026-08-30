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
        # Materialization outcomes where the planid wrote but the entitlement
        # state did NOT update — the org (and every cascaded membership) keeps
        # the PREVIOUS plan's entitlements until a reconcile succeeds. A
        # downgrade in this state must not read as an unqualified success.
        # These are one input to `details.entitlements_ok` (the single wire
        # signal the admin UI keys off to render an error instead of the
        # success toast); a degraded membership cascade is the other — see
        # #entitlement_problem?.
        MATERIALIZATION_PROBLEMS = [:materialization_failed, :plan_not_found].freeze

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
              # Cascade counts from rematerialize_all_memberships! — same
              # wire shape as the reconcile endpoint. null when the run did
              # not cascade (no-op, skips, materialization failure) or the
              # cascade RAISED (on :materialized, nil IS that signal).
              memberships: result.memberships,
              # The one flag the UI keys off: false whenever the planid wrote
              # but entitlement state may not fully match the new plan
              # (materialization problem, partial cascade, or an unobserved
              # cascade outcome). details.message carries the specifics.
              entitlements_ok: !entitlement_problem?,
              message: message,
              warning: stripe_overwrite_warning,
            },
          }
        end

        private

        # True when the planid wrote but the entitlement state may not match
        # the new plan: the engine failed or had no plan definition
        # (MATERIALIZATION_PROBLEMS), the membership cascade partially failed
        # (failed > 0), or the cascade outcome is unobserved (on
        # :materialized a nil memberships means the cascade RAISED — the
        # engine's documented contract). Reconcile is the retry for all of
        # them.
        def entitlement_problem?
          return false unless result.status == :success
          return true if MATERIALIZATION_PROBLEMS.include?(result.materialization)
          return false unless result.materialization == :materialized

          memberships = result.memberships
          memberships.nil? || memberships[:failed].to_i.positive?
        end

        # @return [String] what actually happened, qualified: a plan change
        #   whose entitlement re-materialization or membership cascade did
        #   not complete is NOT an unqualified success (a failed downgrade
        #   would otherwise leave the old plan's premium entitlements active
        #   while telling the operator everything worked).
        def message
          return 'Organization already on this plan' unless result.status == :success

          case result.materialization
          when :materialization_failed
            'Organization plan was saved, but entitlement re-materialization ' \
            'failed — the organization and its members keep the previous ' \
            "plan's entitlements until a reconcile succeeds. Run reconcile " \
            'on this organization.'
          when :plan_not_found
            "Organization plan was saved, but '#{new_planid}' has no " \
            'entitlement definition in the billing catalog, so ' \
            'entitlements were NOT updated — the organization and its ' \
            "members keep the previous plan's entitlements."
          when :materialized
            cascade_message
          else
            'Organization plan updated successfully'
          end
        end

        # @return [String] the :materialized-path message, qualified when the
        #   membership cascade degraded.
        def cascade_message
          memberships = result.memberships
          if memberships.nil?
            'Organization plan updated and entitlements re-materialized, but ' \
              'the membership cascade did not complete — members may keep the ' \
              "previous plan's entitlements. Run reconcile on this organization."
          elsif memberships[:failed].to_i.positive?
            "Organization plan updated, but #{memberships[:failed]} of " \
              "#{memberships[:total]} membership(s) failed to re-materialize " \
              "and keep the previous plan's entitlements. Run reconcile on " \
              'this organization.'
          else
            'Organization plan updated successfully'
          end
        end

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

# lib/onetime/operations/org/set_plan.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + any future CLI), which run outside
# the app autoloaders — require the audit model and the billing engine
# explicitly. Same cross-app require geometry as reconcile.rb (four levels up
# from lib/onetime/operations/org/ to the repo root), minus reconcile's
# `require 'stripe'`: this op never calls the Stripe API (the materialize
# path is purely local), and the gem is deliberately lazy-loaded
# (Gemfile pins it require: false).
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require_relative '../../../../apps/web/billing/operations/apply_subscription_to_org'

module Onetime
  module Operations
    module Org
      # Change an organization's plan (planid) — the SINGLE implementation of
      # the org plan-change verb. The colonel `UpdateOrganizationPlan` Logic
      # class is a thin adapter over it.
      #
      # The customer-level plan change (`Auth::Operations::Customers::SetPlan`)
      # writes the DEPRECATED `Customer#planid` field; the billing relationship
      # actually lives on Organization (Stripe ids, subscription state and the
      # entitlement engine all key off the org), so this op is where an
      # operator-driven plan change belongs. The admin UI's plan control moved
      # from the customer detail page to the organization detail page
      # accordingly.
      #
      # ## What a plan change does
      #
      # 1. Writes `org.planid` and saves.
      # 2. Re-materializes the org's entitlements from the NEW plan via the
      #    same engine the Stripe webhook and reconcile use
      #    ({::Billing::Operations::ApplySubscriptionToOrg
      #    .materialize_entitlements_for_org}), which also cascades to every
      #    active membership. Without this step the plan label changes but the
      #    org keeps the OLD plan's entitlements until the next reconcile —
      #    exactly the drift the sync-status column exists to flag.
      #
      # Operator grant/revoke overrides are PRESERVED: the engine recomputes
      # `materialized = plan ∪ grants − revokes`, re-applying overrides on top
      # (see reconcile.rb "Overrides are PRESERVED, structurally").
      #
      # ## Standalone installs (billing disabled)
      #
      # The planid field is still written (it is plain org state), but the
      # engine is NOT invoked: `WithPlanEntitlements` treats
      # STANDALONE_ENTITLEMENTS as the canonical set regardless of planid, so
      # a materialization keyed off planid would write state the runtime
      # ignores. `materialization` reports :skipped_standalone.
      #
      # ## Stripe-linked orgs
      #
      # A manual plan change on an org with a live Stripe subscription does
      # NOT touch Stripe; the next webhook or reconcile re-derives planid from
      # the subscription and may overwrite this change. That is deliberate —
      # the adapter surfaces a warning so the operator knows to change the
      # subscription in Stripe (or use the checkout flow) when they want the
      # change to stick. Blocking the write instead would leave no escape
      # hatch for exactly the stale-planid repairs this console exists for.
      #
      # ## Exactly-once audit (CONTRACT 4)
      #
      # One {Onetime::ColonelAuditEvent} per successful change, emitted from
      # HERE (adapters MUST NOT audit). An idempotent no-op change mutates
      # nothing and is not audited. A raise partway records `result: :failure`
      # via audit_failures and re-raises.
      class SetPlan
        include Onetime::AuditedFailure

        AUDIT_VERB = 'organization.set_plan'

        # `@org.save` and the engine cascade run BEFORE the success-path
        # record, so a change that half-wrote would otherwise leave the trail
        # claiming nothing happened.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @org&.extid },
          detail: -> { { to: @planid } }

        # @!attribute status [r]
        #   @return [Symbol] :success (plan changed) or :no_change (already on plan)
        # @!attribute materialization [r]
        #   @return [Symbol, nil] the entitlement engine's status
        #     (:materialized, :skipped_no_plan, :plan_not_found, ...),
        #     :skipped_standalone when billing is disabled, nil on :no_change.
        # @!attribute memberships [r]
        #   @return [Hash, nil] membership-cascade counts from the engine
        #     ({success:, failed:, total:, failed_ids:}), when its cascade ran.
        Result = Data.define(:status, :org, :from, :to, :materialization, :memberships)

        # @param org [Onetime::Organization] target (caller resolves; required)
        # @param planid [String, Symbol] target plan id (caller validates
        #   against the billing catalog before calling, mirroring
        #   Customers::SetPlan's adapter contract)
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email). Never an internal objid.
        def initialize(org:, planid:, actor:)
          @org    = org
          @planid = planid.to_s
          @actor  = actor
        end

        # @return [Result]
        def call
          from = @org.planid.to_s
          if from == @planid
            return Result.new(
              status: :no_change,
              org: @org,
              from: from,
              to: @planid,
              materialization: nil,
              memberships: nil,
            )
          end

          @org.planid = @planid
          @org.save

          materialization, memberships = materialize_entitlements

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :success,
            detail: { from: from, to: @planid, materialization: materialization },
          )

          Result.new(
            status: :success,
            org: @org,
            from: from,
            to: @planid,
            materialization: materialization,
            memberships: memberships,
          )
        end

        private

        # Re-materialize entitlements from the new plan. DEGRADABLE: the
        # planid write has already committed and is the operator's primary
        # intent; an engine failure here must surface as a status they can act
        # on (reconcile retries the same engine), not roll back the plan
        # change or 500 the endpoint.
        #
        # @return [Array(Symbol, Hash|nil)] [materialization status, cascade counts]
        def materialize_entitlements
          return [:skipped_standalone, nil] unless billing_enabled?

          result = ::Billing::Operations::ApplySubscriptionToOrg
            .materialize_entitlements_for_org(@org)
          [result.status, result.memberships]
        rescue StandardError => ex
          OT.le '[org.set_plan] entitlement materialization failed',
            org_extid: @org.extid,
            planid: @planid,
            exception: ex,
            message: ex.message
          [:materialization_failed, nil]
        end

        # WithEntitlements#billing_enabled? already rescues to false, so a
        # broken BillingConfig degrades to the standalone (field-only) write
        # rather than raising — the same polarity as reconcile.
        def billing_enabled?
          @org.billing_enabled?
        end
      end
    end
  end
end

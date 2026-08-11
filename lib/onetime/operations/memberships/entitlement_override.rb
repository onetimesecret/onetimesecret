# lib/onetime/operations/memberships/entitlement_override.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model explicitly. The org-level op is the
# authority on the entitlement catalog predicate; require it so
# {.known_entitlement?} can delegate rather than fork.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/operations/org/entitlement_override'

module Onetime
  module Operations
    module Memberships
      # Grant / revoke / clear a MEMBERSHIP's operator entitlement overrides —
      # the SINGLE implementation of the membership-scoped entitlement-override
      # verb (#3907, closing D19 of #3731). The colonel endpoints
      # (`POST /api/colonel/organizations/:org_id/members/:member_id/entitlements/:action`
      # and `DELETE …/members/:member_id/entitlements/overrides`) and the
      # `bin/ots memberships entitlement …` CLI are thin adapters over it.
      #
      # This is the deliberate sibling of
      # {Onetime::Operations::Org::EntitlementOverride}: same actions, same
      # statuses, same dry-run default, same D15 no-change asymmetry, same
      # warn-don't-block stance on unknown entitlements. It differs ONLY where
      # membership scope forces it to:
      #
      # - The target is a membership, resolved here from org + customer (the
      #   pair IS the membership's identity — precedent: memberships/set_role.rb).
      #   A missing or inactive membership returns `:not_found`.
      # - The audit verb prefix is `membership.entitlement` and the audit
      #   target is the CUSTOMER's extid, so `detail` always carries `org_id`
      #   (matching membership.set_role) — target alone cannot identify the
      #   membership. That is why clear's detail is `{ org_id: }` here rather
      #   than the org op's `{}`.
      # - {Result} carries `member_id` alongside `org_id`.
      #
      # ## What a membership override actually is
      #
      # `OrganizationMembership` carries the same two operator-owned sets as
      # `Organization` (declared in MembershipMaterializedEntitlements):
      # `entitlements_grants` and `entitlements_revokes`. Every materialization
      # recomputes `materialized = entitlements_plan ∪ grants − revokes`
      # (`apply_entitlements`), and `materialize_for_role!` rewrites ONLY
      # `entitlements_plan` (org ∩ role template) before re-reconciling — so
      # membership overrides SURVIVE role changes, org plan changes and
      # `rematerialize_all_memberships!` by construction.
      #
      # ## A membership grant is NOT bounded by org plan or role template
      #
      # The plan set is intersected (org ∩ role); the grants set is unioned on
      # top with NO intersection. A membership-level grant therefore reaches
      # `can?` directly, even for an entitlement outside the member's role
      # template or the org's plan. That reach is the point of the verb — the
      # CLI warns so an operator grants it knowingly.
      #
      # ## Standalone installs behave DIFFERENTLY from org scope
      #
      # The org-level write is a dead letter when billing is disabled
      # (`Organization#entitlements` short-circuits to STANDALONE_ENTITLEMENTS).
      # The membership read path has NO such short-circuit: a materialized
      # membership answers `can?` from `materialized_entitlements` regardless
      # of billing. On a standalone install the membership's plan baseline
      # derives from STANDALONE_ENTITLEMENTS ∩ role (already full role access),
      # so grants mostly add nothing while revokes DO bite. `standalone: true`
      # is surfaced on {Result} for adapters to explain exactly that.
      #
      # ## Not in scope
      #
      # No override TTL/expiry — #3905 has not landed; overrides are permanent
      # until cleared, matching org-level semantics exactly so the two surfaces
      # stay symmetric.
      class EntitlementOverride
        include Onetime::AuditedFailure

        ACTIONS = Org::EntitlementOverride::ACTIONS

        # Operator-facing past tense — shared with the org op so the two HTTP
        # surfaces render identical `action` strings.
        ACTION_PAST_TENSE = Org::EntitlementOverride::ACTION_PAST_TENSE

        # Emitted verb is "#{AUDIT_VERB_PREFIX}.#{action}" — membership-scoped,
        # sibling of `organization.entitlement.*` and `membership.set_role`.
        AUDIT_VERB_PREFIX = 'membership.entitlement'

        # Status -> the applied status symbol for that action.
        APPLIED_STATUS = Org::EntitlementOverride::APPLIED_STATUS

        # Statuses an adapter should treat as "the op did what was asked".
        # Everything else (`:invalid_action`, `:missing_entitlement`,
        # `:not_found`) is an operator-visible failure.
        OK_STATUSES = Org::EntitlementOverride::OK_STATUSES

        # The complement of OK_STATUSES: each records one `result: :failure`
        # event. Derived from the org op (never a hardcoded fork) plus the ONE
        # status membership scope adds — the membership is resolved here, so it
        # can be missing in a way the org op's caller-resolved org cannot.
        REFUSAL_STATUSES = (Org::EntitlementOverride::REFUSAL_STATUSES + [:not_found]).freeze

        # grant/revoke/clear write Familia sets and re-reconcile materialized
        # entitlements; a raise mid-apply leaves the membership's effective
        # permissions unknown, and the success record sits after apply!. Records
        # one `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only — without it a blown-up preview is
        # indistinguishable from a blown-up override.
        audit_failures :call,
          verb: -> { audit_verb },
          target: -> { @customer&.extid },
          detail: -> { { dry_run: @dry_run, org_id: @org&.extid, action: @action } }

        # @!attribute status [r] Symbol — :granted | :revoked | :cleared |
        #   :no_change | :planned | :invalid_action | :missing_entitlement |
        #   :not_found
        # @!attribute org_id [r] String — the org's PUBLIC id (extid). Never an objid.
        # @!attribute member_id [r] String — the member customer's PUBLIC id (extid).
        # @!attribute action [r] String — the normalized action ('grant'/'revoke'/'clear').
        # @!attribute entitlement [r] String, nil — nil for clear.
        # @!attribute effective [r] Array<String>, nil — the membership's
        #   materialized entitlements after the run; on a dry run this is the
        #   PROJECTED set (plan ∪ grants − revokes with the change applied).
        # @!attribute grants [r] Array<String>, nil — override grants after the run.
        # @!attribute revokes [r] Array<String>, nil — override revokes after the run.
        # @!attribute standalone [r] Boolean — true when billing is disabled on
        #   this install. Unlike org scope the write is still read at runtime;
        #   adapters explain the different failure mode.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :member_id,
          :action,
          :entitlement,
          :effective,
          :grants,
          :revokes,
          :standalone,
          :dry_run,
        )

        # Is this entitlement name present in the billing catalog?
        # Delegates to the org op — one catalog, one predicate. Exposed for
        # ADAPTERS to warn on a typo; `#call` deliberately never consults it.
        #
        # @param name [String]
        # @return [Boolean]
        def self.known_entitlement?(name)
          Org::EntitlementOverride.known_entitlement?(name)
        end

        # @param org [Onetime::Organization] the membership's org (caller resolves; required).
        # @param customer [Onetime::Customer] the member whose overrides change.
        # @param action [String, Symbol] 'grant' | 'revoke' | 'clear'.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param entitlement [String, nil] required for grant/revoke, ignored by clear.
        # @param dry_run [Boolean] preview only when true (the safe default —
        #   `clear` wipes EVERY override on the membership).
        def initialize(org:, customer:, action:, actor:, entitlement: nil, dry_run: true)
          @org         = org
          @customer    = customer
          @action      = action.to_s.strip.downcase
          @actor       = actor
          # `clear` ignores any supplied entitlement — store nil so the Result
          # and audit trail never carry input the action doesn't read.
          @entitlement = @action == 'clear' ? nil : entitlement.to_s.strip
          @dry_run     = dry_run
        end

        # @return [Result]
        def call
          return build(:invalid_action) unless ACTIONS.include?(@action)
          return build(:missing_entitlement) if @action != 'clear' && @entitlement.empty?

          membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
          return build(:not_found) unless membership&.active?

          # Read the current override sets ONCE, before any mutation: they drive
          # both the no-change check and the dry-run projection.
          grants  = membership.entitlements_grants.to_a
          revokes = membership.entitlements_revokes.to_a

          # D15: grant/revoke short-circuit when already in the requested state.
          # `clear` never does — it always applies and always audits.
          if no_change?(grants, revokes)
            return build(
              :no_change,
              effective: membership.materialized_entitlements.to_a,
              grants: grants,
              revokes: revokes,
            )
          end

          if @dry_run
            projected_grants, projected_revokes = project(grants, revokes)
            return build(
              :planned,
              effective: project_effective(membership, projected_grants, projected_revokes),
              grants: projected_grants,
              revokes: projected_revokes,
            )
          end

          apply!(membership)

          # One audit event per applied override change (CONTRACT 4 / epic D4),
          # emitted from HERE. Adapters MUST NOT audit or the trail
          # double-records. `detail` always carries org_id (the target is the
          # customer; org_id completes the membership identity). The cleared
          # set stays unrecorded — it is unbounded, matching the org op.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: audit_verb,
            target: @customer.extid,
            result: :success,
            detail: audit_detail,
          )

          build(
            APPLIED_STATUS[@action],
            effective: membership.materialized_entitlements.to_a,
            grants: membership.entitlements_grants.to_a,
            revokes: membership.entitlements_revokes.to_a,
          )
        end

        private

        # "membership.entitlement.<action>" — BYTE-IDENTICAL to what the success
        # path has always emitted for a valid action (a frontend filter
        # prefix-matches these). An INVALID action falls back to the bare prefix
        # rather than interpolating operator-supplied text into the verb: the
        # verb namespace is a closed set, and an :invalid_action refusal has no
        # success-path verb to match.
        def audit_verb
          ACTIONS.include?(@action) ? "#{AUDIT_VERB_PREFIX}.#{@action}" : AUDIT_VERB_PREFIX
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op. `dry_run` is carried so a refused preview is distinguishable
        # from a refused apply.
        def record_refusal(status)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: audit_verb,
            target: @customer.extid,
            result: :failure,
            detail: {
              reason: status.to_s,
              org_id: @org.extid,
              action: @action,
              entitlement: @entitlement,
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          OT.le "[Memberships::EntitlementOverride] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        def apply!(membership)
          case @action
          when 'grant'  then membership.grant_entitlement(@entitlement)
          when 'revoke' then membership.revoke_entitlement(@entitlement)
          when 'clear'  then membership.clear_entitlement_overrides
          end
        end

        def audit_detail
          detail                = { org_id: @org.extid }
          detail[:entitlement]  = @entitlement unless @action == 'clear'
          detail
        end

        # Membership in the sets is checked EXPLICITLY rather than trusting the
        # boolean returned by `Set#add` — the model's grant/revoke each perform
        # a remove on the opposite set first, so the add's return value alone
        # cannot tell "already exactly in this state" from "moved between sets".
        def no_change?(grants, revokes)
          case @action
          when 'grant'  then grants.include?(@entitlement) && !revokes.include?(@entitlement)
          when 'revoke' then revokes.include?(@entitlement) && !grants.include?(@entitlement)
          else false # 'clear' ALWAYS applies (D15)
          end
        end

        # The override sets as they WOULD be after this action.
        def project(grants, revokes)
          case @action
          when 'grant'  then [(grants | [@entitlement]), (revokes - [@entitlement])]
          when 'revoke' then [(grants - [@entitlement]), (revokes | [@entitlement])]
          else [[], []]
          end
        end

        # Mirror of the model's `apply_entitlements` reconciliation
        # (plan ∪ grants − revokes) against a projected pair of override sets.
        # Never written anywhere — dry runs mutate nothing.
        def project_effective(membership, grants, revokes)
          ((membership.entitlements_plan.to_a | grants) - revokes).sort
        end

        # Single exit point for every non-applied status, so the refusal audit
        # cannot be forgotten at one of the four early returns.
        def build(status, effective: nil, grants: nil, revokes: nil)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            org_id: @org.extid,
            member_id: @customer.extid,
            action: @action,
            entitlement: @entitlement,
            effective: effective,
            grants: grants,
            revokes: revokes,
            standalone: !@org.billing_enabled?,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end

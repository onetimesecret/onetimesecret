# lib/onetime/operations/org/entitlement_override.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model explicitly.
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Org
      # Grant / revoke / clear an organization's operator entitlement overrides —
      # the SINGLE implementation of the entitlement-override verb (#3731). The
      # colonel endpoints (`POST /api/colonel/organizations/:org_id/entitlements/:action`
      # and `DELETE …/entitlements/overrides`) and the `bin/ots org entitlement …`
      # CLI are thin adapters over it.
      #
      # This is an EXTRACTION of ColonelAPI::Logic::Colonel::ManageEntitlementOverride,
      # which carried the comment "this billing-domain verb has no extracted
      # Operation yet … so the non-negotiable audit backstop lives here". This op
      # is that Operation; the backstop moved here and the adapter MUST NOT audit.
      #
      # ## What an override actually is
      #
      # `Organization` carries two operator-owned sets (declared in
      # Onetime::Models::Features::WithMaterializedEntitlements):
      # `entitlements_grants` and `entitlements_revokes`. Every materialization
      # recomputes `materialized = entitlements_plan ∪ grants − revokes`
      # (`apply_entitlements`), so overrides SURVIVE plan changes and reconciles
      # by construction — no reconcile path clears those two sets.
      #
      # The three model methods this op dispatches to already reconcile
      # internally, so the op never touches `materialized_entitlements` itself:
      #
      # - `grant_entitlement(e)`   — revokes.remove(e), grants.add(e), reconcile
      # - `revoke_entitlement(e)`  — grants.remove(e), revokes.add(e), reconcile
      # - `clear_entitlement_overrides` — clears BOTH sets, reconcile
      #
      # ## No-change semantics are DELIBERATELY asymmetric (D15)
      #
      # `grant` and `revoke` are idempotent and cheaply detectable: if the
      # entitlement is already in the target set and absent from the opposite
      # set, the op returns `:no_change` and mutates/audits NOTHING.
      #
      # `clear` ALWAYS applies and ALWAYS audits, even when both sets are already
      # empty. It is not a cheap check (the sets are the state, and "already
      # empty" is indistinguishable from "cleared" to a later reader), and
      # try/integration/api/colonel/manage_entitlement_override_try.rb asserts
      # the `organization.entitlement.clear` audit event unconditionally. Do not
      # "fix" this into symmetry.
      #
      # ## Unknown entitlements WARN, they do not block
      #
      # {.known_entitlement?} is exposed for adapters, but `#call` never consults
      # it. Granting an entitlement that ships in a LATER billing catalog is a
      # supported operator move (pre-seeding a rollout); refusing it here would
      # break that. The pre-extraction endpoint made the same choice explicitly.
      #
      # ## Standalone installs: the write is a DEAD LETTER (D17)
      #
      # `WithPlanEntitlements#entitlements` short-circuits on `!billing_enabled?`
      # and returns `STANDALONE_ENTITLEMENTS` BEFORE it ever reaches the
      # materialized path. On a billing-disabled (self-hosted) install the
      # override is written to Redis, `materialized_entitlements` is recomputed —
      # and every runtime `can?` check ignores all of it. Worse, `bin/ots org
      # entitlement show` reads those sets directly, so it looks like it worked.
      #
      # The op does NOT refuse (that would break pre-seeding an install which
      # enables billing later). It surfaces `standalone: true` on {Result} and
      # both adapters MUST warn as loudly as their medium allows.
      #
      # ## Org scope is not member scope
      #
      # An org-level grant only reaches a member whose role template contains it:
      # `materialize_for_role!` intersects `org.entitlements & ROLE_ENTITLEMENTS[role]`.
      # Granting an entitlement absent from every role template changes nothing a
      # member can see.
      #
      # ## Not in scope (see decisions D18/D19)
      #
      # - No override TTL/expiry (D18) — overrides are permanent until cleared.
      # - No membership-level overrides (D19) — `OrganizationMembership` has the
      #   same three methods with zero adapters. The commands are named
      #   `org entitlement …` deliberately so a future `memberships entitlement …`
      #   is shape-compatible.
      class EntitlementOverride
        ACTIONS = %w[grant revoke clear].freeze

        # Operator-facing past tense. Moved verbatim from the colonel logic,
        # which still renders it in its HTTP `action` field.
        ACTION_PAST_TENSE = {
          'grant' => 'granted',
          'revoke' => 'revoked',
          'clear' => 'cleared',
        }.freeze

        # Emitted verb is "#{AUDIT_VERB_PREFIX}.#{action}" — BYTE-IDENTICAL to
        # the pre-extraction value. The existing trail and the colonel tryout
        # gate both match on those exact strings.
        AUDIT_VERB_PREFIX = 'organization.entitlement'

        # Status -> the applied status symbol for that action.
        APPLIED_STATUS = {
          'grant' => :granted,
          'revoke' => :revoked,
          'clear' => :cleared,
        }.freeze

        # Statuses an adapter should treat as "the op did what was asked".
        # Everything else (`:invalid_action`, `:missing_entitlement`) is an
        # operator-visible failure.
        OK_STATUSES = [
          :granted,
          :revoked,
          :cleared,
          :no_change,
          :planned,
        ].freeze

        # @!attribute status [r] Symbol — :granted | :revoked | :cleared |
        #   :no_change | :planned | :invalid_action | :missing_entitlement
        # @!attribute org_id [r] String — the org's PUBLIC id (extid). Never an objid.
        # @!attribute action [r] String — the normalized action ('grant'/'revoke'/'clear').
        # @!attribute entitlement [r] String, nil — nil for clear.
        # @!attribute effective [r] Array<String>, nil — materialized entitlements
        #   after the run; on a dry run this is the PROJECTED set
        #   (plan ∪ grants − revokes with the change applied), not a read.
        # @!attribute grants [r] Array<String>, nil — override grants after the run.
        # @!attribute revokes [r] Array<String>, nil — override revokes after the run.
        # @!attribute standalone [r] Boolean — true when billing is disabled on
        #   this install, i.e. the write has NO read-path effect. Adapters warn.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :action,
          :entitlement,
          :effective,
          :grants,
          :revokes,
          :standalone,
          :dry_run,
        )

        # Is this entitlement name present in the billing catalog?
        #
        # Exposed for ADAPTERS to warn on a typo. `#call` deliberately never
        # consults it — see the class comment. Returns true when the catalog is
        # unavailable so a missing/unloadable billing config can never turn into
        # a spurious "unknown entitlement" warning.
        #
        # @param name [String]
        # @return [Boolean]
        def self.known_entitlement?(name)
          return true unless defined?(::Billing::Config)

          ::Billing::Config.load_entitlements.key?(name.to_s)
        rescue StandardError
          true
        end

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param action [String, Symbol] 'grant' | 'revoke' | 'clear'.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param entitlement [String, nil] required for grant/revoke, ignored by clear.
        # @param dry_run [Boolean] preview only when true (the safe default —
        #   `clear` wipes EVERY override on the org).
        def initialize(org:, action:, actor:, entitlement: nil, dry_run: true)
          @org         = org
          @action      = action.to_s.strip.downcase
          @actor       = actor
          @entitlement = entitlement.to_s.strip
          @dry_run     = dry_run
        end

        # @return [Result]
        def call
          return build(:invalid_action) unless ACTIONS.include?(@action)
          return build(:missing_entitlement) if @action != 'clear' && @entitlement.empty?

          # Read the current override sets ONCE, before any mutation: they drive
          # both the no-change check and the dry-run projection.
          grants  = @org.entitlements_grants.to_a
          revokes = @org.entitlements_revokes.to_a

          # D15: grant/revoke short-circuit when already in the requested state.
          # `clear` never does — it always applies and always audits.
          if no_change?(grants, revokes)
            return build(
              :no_change,
              effective: @org.materialized_entitlements.to_a,
              grants: grants,
              revokes: revokes,
            )
          end

          if @dry_run
            projected_grants, projected_revokes = project(grants, revokes)
            return build(
              :planned,
              effective: project_effective(projected_grants, projected_revokes),
              grants: projected_grants,
              revokes: projected_revokes,
            )
          end

          apply!

          # One audit event per applied override change (CONTRACT 4 / epic D4),
          # emitted from HERE. Adapters MUST NOT audit or the trail
          # double-records. `detail` for clear stays {} — the cleared set is
          # unbounded and the pre-extraction endpoint recorded {} too.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: "#{AUDIT_VERB_PREFIX}.#{@action}",
            target: @org.extid,
            result: :success,
            detail: @action == 'clear' ? {} : { entitlement: @entitlement },
          )

          build(
            APPLIED_STATUS[@action],
            effective: @org.materialized_entitlements.to_a,
            grants: @org.entitlements_grants.to_a,
            revokes: @org.entitlements_revokes.to_a,
          )
        end

        private

        def apply!
          case @action
          when 'grant'  then @org.grant_entitlement(@entitlement)
          when 'revoke' then @org.revoke_entitlement(@entitlement)
          when 'clear'  then @org.clear_entitlement_overrides
          end
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
        def project_effective(grants, revokes)
          ((@org.entitlements_plan.to_a | grants) - revokes).sort
        end

        def build(status, effective: nil, grants: nil, revokes: nil)
          Result.new(
            status: status,
            org_id: @org.extid,
            action: @action,
            entitlement: @action == 'clear' ? nil : @entitlement,
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

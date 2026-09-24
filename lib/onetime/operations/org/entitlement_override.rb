# lib/onetime/operations/org/entitlement_override.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

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
      # set, the op returns `:no_change` and mutates NOTHING. Since #4337 the
      # attempt is still recorded: a LIVE no-change lands on the OPERATOR trail
      # under the same verb with `outcome: 'no_change'`, and a dry-run
      # no-change stays on the OBSERVATION trail as a preview (previews never
      # touch the operator trail, and `dry_run` defaults to true here).
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
        include Onetime::AuditedFailure

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

        # The complement of OK_STATUSES: a privileged mutation was asked for and
        # REFUSED. Each records one `result: :failure` event, for the same reason
        # the raising privilege guard in
        # {Auth::Operations::Customers::SetSuspension} does — whether a refusal
        # comes back as a Result or an exception must not decide whether it is
        # traceable. `:no_change`/`:planned` are excluded: nothing was refused.
        REFUSAL_STATUSES = [
          :invalid_action,
          :missing_entitlement,
        ].freeze

        # grant/revoke/clear write Familia sets and re-reconcile the org's
        # materialized entitlements; a raise mid-apply leaves the org's effective
        # permissions unknown, and the success record sits after apply!. Records
        # one `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only.
        audit_failures :call,
          verb: -> { audit_verb },
          target: -> { @org&.extid },
          detail: -> { { dry_run: @dry_run, action: @action } }

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
          # `clear` never does — it always applies and always audits. The
          # short-circuit still records (#4337), split by intent: a live call
          # is a mutation ATTEMPT (operator trail, outcome: 'no_change'), while
          # a dry-run call is a preview that found nothing to do — it stays an
          # observation, exactly like the :planned path below, so the default
          # preview-first workflow never writes operator-trail rows.
          if no_change?(grants, revokes)
            if @dry_run
              record_preview_event(outcome: 'no_change')
            else
              record_no_change_event
            end
            return build(
              :no_change,
              effective: @org.materialized_entitlements.to_a,
              grants: grants,
              revokes: revokes,
            )
          end

          if @dry_run
            projected_grants, projected_revokes = project(grants, revokes)
            # Mutates nothing, so nothing reaches the OPERATOR trail — but a
            # preview shows what an override would do to a paying org's
            # entitlements, so it is recorded as an OBSERVATION (#4337).
            record_preview_event
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
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: audit_verb,
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

        # "organization.entitlement.<action>" — BYTE-IDENTICAL to the
        # pre-extraction value for a valid action (the existing trail and the
        # colonel tryout gate match those exact strings). An INVALID action falls
        # back to the bare prefix rather than interpolating operator-supplied
        # text into the verb: the verb namespace is a closed set, and an
        # :invalid_action refusal has no success-path verb to match.
        def audit_verb
          ACTIONS.include?(@action) ? "#{AUDIT_VERB_PREFIX}.#{@action}" : AUDIT_VERB_PREFIX
        end

        # One OBSERVATION per preview (#4337), on the budgeted access trail.
        # Same verb and target as the applied event, so a preview and the
        # override that followed read as one sequence; `result: 'preview'`
        # tells them apart. The projected entitlement SETS stay out — they are
        # plan output for the operator, and `clear`'s set is unbounded (the
        # same reason the applied event's detail is {} for clear). `outcome`
        # is set (to 'no_change') when the preview short-circuited on D15.
        def record_preview_event(outcome: nil)
          detail           = { dry_run: true, action: @action, entitlement: @entitlement }
          detail[:outcome] = outcome if outcome

          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: audit_verb,
            target: @org.extid,
            result: 'preview',
            detail: detail,
          )
        end

        # A LIVE no-change attempt (#4337) — the OPERATOR trail. Re-granting an
        # entitlement an org already holds is the same reach as the grant that
        # changed it, and a trail that goes quiet for it can show nothing while
        # an operator repeatedly probes an org. Same verb and target as the
        # applied event; detail keeps the applied event's shape (the verb
        # carries the action) plus the `outcome: 'no_change'` marker. NOT
        # fail-closed: nothing moved.
        def record_no_change_event
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: audit_verb,
            target: @org.extid,
            result: :success,
            detail: { outcome: 'no_change', entitlement: @entitlement },
          )
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: audit_verb,
            target: @org.extid,
            result: :failure,
            detail: {
              reason: status.to_s,
              action: @action,
              entitlement: @entitlement,
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          OT.le "[Org::EntitlementOverride] refusal audit failed: #{ex.class}: #{ex.message}"
        end

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

        # Single exit point for every non-applied status, so the refusal audit
        # cannot be forgotten at an early return.
        def build(status, effective: nil, grants: nil, revokes: nil)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

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

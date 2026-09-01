# lib/onetime/operations/org/reconcile.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model and the billing engine explicitly.
#
# CROSS-APP REQUIRE, verified with File.expand_path: from
# lib/onetime/operations/org/ the repo root is FOUR levels up
# (org -> operations -> onetime -> lib -> ROOT). The colonel logic reaches the
# same file from FIVE (colonel -> logic -> colonel -> api -> apps -> ROOT), so
# do NOT copy its `../` count. A wrong count fails only at CLI runtime, outside
# the app autoloaders — a spec that loads billing another way will NOT catch it.
require 'stripe'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require_relative '../../../../apps/web/billing/operations/apply_subscription_to_org'

module Onetime
  module Operations
    # Organization lifecycle + remediation verbs (#3731).
    #
    # Placement (D10): `Organization` / `OrganizationMembership` are
    # lib/onetime/models-owned with no owning app, so their verbs live here and
    # not in apps/web/billing/operations. Billing is a DEPENDENCY of reconcile,
    # not its owner. Matches the `Onetime::Operations::Memberships::` precedent.
    #
    # CONSTANT-LOOKUP TRAP: `Onetime::Operations::Billing` EXISTS
    # (lib/onetime/operations/billing/). Inside this namespace a bare
    # `Billing::Operations::ApplySubscriptionToOrg` therefore resolves `Billing`
    # to `Onetime::Operations::Billing` and blows up on `::Operations` — but
    # only once that file happens to be loaded, i.e. intermittently. Always
    # write `::Billing::…` here. For the same reason, fully qualify
    # `Onetime::Organization` / `Onetime::Customer` /
    # `Onetime::OrganizationMembership` (precedent: memberships/set_role.rb:64).
    module Org
      # Reconcile an organization's billing + entitlement state — the SINGLE
      # implementation of the reconcile verb (#3731). The colonel endpoint
      # (`POST /api/colonel/organizations/:org_id/reconcile`) and the
      # `bin/ots org reconcile` CLI are thin adapters over it.
      #
      # This is an EXTRACTION of ColonelAPI::Logic::Colonel::ReconcileOrganization,
      # not a reimplementation. The engine stays
      # {::Billing::Operations::ApplySubscriptionToOrg} — the same path the Stripe
      # webhook uses, so an operator-triggered reconcile and a webhook converge on
      # identical state. This op is the audited, dry-run-capable, status-routing
      # wrapper both adapters share.
      #
      # ## Two modes (selected on `billing_enabled?`, then `stripe_subscription_id`)
      #
      # - `stripe_sync` — re-pull the live subscription and apply it (planid,
      #   subscription_status, period_end, Stripe ids, then re-materialize
      #   entitlements + memberships).
      # - `entitlements_only` — no Stripe billing to sync; re-materialize
      #   entitlements from the org's current plan, which clears entitlement
      #   drift (e.g. an orphaned entry left in `materialized`). This mode covers
      #   TWO materializers: the plan-driven engine when billing is enabled, and
      #   `materialize_standalone_entitlements!` when it is not (see below). The
      #   `status` distinguishes them; `mode` deliberately does not.
      #
      # ## Standalone mode (billing disabled — D13)
      #
      # `billing_enabled? == false` is checked FIRST, ahead of the
      # `stripe_subscription_id` mode selection: on a self-hosted install a
      # leftover subscription id must not send reconcile to Stripe, and
      # `WithPlanEntitlements` treats STANDALONE_ENTITLEMENTS as the canonical
      # set regardless of `planid`. The branch calls
      # `materialize_standalone_entitlements!` then cascades with
      # `rematerialize_all_memberships!` (the same pair the
      # `materialize_standalone_entitlements` chore runs), and returns
      # `:standalone`.
      #
      # This CLOSES A DEAD END: before D13 a billing-disabled reconcile fell
      # through to the plan engine, which returns `:skipped_no_plan` for an org
      # with no planid (apply_subscription_to_org.rb) — the operator pressed
      # reconcile and nothing happened, while
      # `WithPlanEntitlements#materialize_standalone_entitlements!` had existed
      # the whole time. It is a LIVE BEHAVIOUR CHANGE on every billing-disabled
      # install reached through the existing colonel endpoint, and it cascades
      # to every membership — hence its own PR.
      #
      # Unlike the chore, reconcile re-materializes an ALREADY-materialized org.
      # That is the verb's job (repair drift), and it is safe: the standalone
      # materializer routes through `materialize_entitlements_from_config` ->
      # `apply_entitlements`, which re-applies `grants − revokes` on top. The
      # chore's "already materialized -> skip" branch is backfill-specific.
      #
      # WIRE NOTE: the standalone branch reports `mode: 'entitlements_only'`, NOT
      # a third mode string. `mode` is consumed by a CLOSED zod enum —
      # src/schemas/api/internal/responses/colonel-organizations.ts
      # `colonelReconcileOrganizationRecordSchema` declares
      # `z.enum(['stripe_sync', 'entitlements_only'])` — so a new value would
      # fail response validation in the admin UI on exactly the self-hosted
      # installs this branch serves. `status` is `z.string()` and carries the
      # distinction instead. Do not "fix" this without shipping the enum change
      # in the same PR.
      #
      # ## Overrides are PRESERVED, structurally
      #
      # No reconcile path clears `entitlements_grants` / `entitlements_revokes`.
      # `materialize_entitlements_from_plan` clears only `entitlements_plan` +
      # `limits_plan`, then `apply_entitlements` recomputes
      # `materialized = plan ∪ grants − revokes`. Operator overrides are
      # re-applied on top on every run, by design. Do not add a "clean" path
      # here that touches those sets.
      #
      # ## Exactly-once audit (CONTRACT 4)
      #
      # An applied run records EXACTLY ONE {Onetime::ColonelAuditEvent} with verb
      # {AUDIT_VERB}, emitted from HERE. Adapters MUST NOT audit. The event is
      # unconditional on every applied path — including the "nothing to do"
      # statuses (`:skipped_no_plan`, `:plan_not_found`) — because an operator
      # pressing reconcile is itself the auditable act, and because that is the
      # pre-extraction behaviour the trail and
      # try/integration/api/colonel/get_organization_detail_try.rb depend on.
      # A dry run records nothing (nothing was attempted against the org).
      #
      # `result:` is DERIVED from {OK_STATUSES} rather than pinned to :success
      # (the {Onetime::Operations::AdminVerifyDomain} pattern): a reconcile that
      # could not find the org's plan is a failed reconcile, and labelling it
      # :success made the trail disagree with the op's own status vocabulary. A
      # `:stripe_error` — previously the one applied-path outcome that recorded
      # NOTHING — now records `result: :failure` too; the operator attempted the
      # mutation and Stripe refused it. The verb is unchanged on every path.
      #
      # ## Status vocabulary
      #
      # Deliberately the SAME strings the pre-extraction colonel response
      # emitted (`applied` for stripe_sync, the raw
      # {::Billing::Operations::MaterializeResult} status for entitlements_only),
      # so `result.status.to_s` keeps the HTTP payload byte-identical.
      #
      # ## Not in scope here (see decision D12)
      #
      # - No colonel dry-run preview (D12) — the op supports `dry_run`, the
      #   colonel adapter pins it to false. Deferred until the admin UI grows a
      #   confirm-preview flow (#3907 item 4).
      #
      # ## Membership-cascade counts (D14, superseded by #3907 item 3)
      #
      # D14 originally left the cascade counts out of {Result} because
      # `execute_materialize` only logged them. The engine's
      # {::Billing::Operations::MaterializeResult} now carries them
      # (`memberships`), so every APPLIED path populates {Result#memberships}
      # without re-running the cascade: stripe_sync reads the engine instance's
      # result, entitlements_only passes the engine field through, and the
      # standalone branch reports its own cascade. nil marks the paths where
      # the cascade genuinely did not run (dry runs, skips, errors) — and the
      # applied paths where it RAISED, which the logs cover.
      class Reconcile
        include Onetime::AuditedFailure

        # Audit verb recorded for every applied reconcile. BYTE-IDENTICAL to the
        # pre-extraction value — the existing trail and the colonel tryout gate
        # both match on this exact string.
        AUDIT_VERB = 'organization.reconcile'

        MODE_STRIPE_SYNC       = 'stripe_sync'
        MODE_ENTITLEMENTS_ONLY = 'entitlements_only'

        # Statuses an adapter should treat as "reconcile did what it could".
        # Everything else (`:skipped_no_plan`, `:plan_not_found`,
        # `:stripe_error`) is an operator-visible failure.
        OK_STATUSES = [
          :applied,            # stripe_sync applied
          :materialized,       # entitlements_only applied
          :standalone,         # entitlements_only applied, billing disabled (D13)
          :skipped_fresh,      # entitlements already current
          :planned,            # stripe_sync OR standalone dry run
          :would_materialize,  # entitlements_only dry run
        ].freeze

        # A reconcile rewrites planid / subscription_status / materialized
        # entitlements and CASCADES to every membership. A raise partway leaves
        # the org and its members in an unknown entitlement state, and the
        # success-path record sits after the whole dispatch. Records one
        # `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @org&.extid },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol — :applied | :materialized |
        #   :standalone | :skipped_no_plan | :skipped_fresh | :plan_not_found |
        #   :planned | :would_materialize | :stripe_error
        # @!attribute org_id [r] String — the org's PUBLIC id (extid). Never an objid.
        # @!attribute mode [r] String — MODE_STRIPE_SYNC or MODE_ENTITLEMENTS_ONLY.
        # @!attribute before [r] Hash — billing snapshot taken before the run.
        # @!attribute after [r] Hash, nil — snapshot after the run; nil on a dry
        #   run and on :stripe_error (nothing was written, and a projected
        #   "after" would be a re-derivation that can disagree with an apply —
        #   ApplySubscriptionToOrg has no dry-run mode).
        # @!attribute reason [r] String, nil — human-readable skip/error reason.
        # @!attribute memberships [r] Hash, nil — membership-cascade counts
        #   ({success:, failed:, total:, failed_ids:}) from
        #   `rematerialize_all_memberships!`, present on the applied statuses
        #   whose run cascaded (:applied, :materialized, :standalone); nil on
        #   dry runs, skips and errors, and on an applied run whose cascade
        #   raised (see logs). EXCEPTION to the extid-only rule: `failed_ids`
        #   are membership OBJIDs, verbatim from the cascade — that is the
        #   identifier operator follow-up (`bin/ots memberships doctor`) works
        #   in, and there may be no live customer behind a failed membership to
        #   resolve an extid from.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(:status, :org_id, :mode, :before, :after, :reason, :memberships, :dry_run) do
          # Defaulted so pre-#3907 keyword constructors (adapter specs) and the
          # cascade-free build paths need no churn.
          def initialize(status:, org_id:, mode:, before:, after:, reason:, dry_run:, memberships: nil)
            super
          end
        end

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param dry_run [Boolean] preview only when true (the safe default —
        #   this rewrites planid / subscription_status / materialized
        #   entitlements and cascades to every membership).
        def initialize(org:, actor:, dry_run: true)
          @org        = org
          @actor      = actor
          @dry_run    = dry_run
          @standalone = nil # memo for #standalone?
        end

        # @return [Result]
        def call
          org_extid = @org.extid
          before    = snapshot(@org)
          mode      = resolve_mode

          outcome = dispatch(mode)

          # A dry run wrote nothing and attempted nothing: no reload, no
          # snapshot, no OPERATOR event. It is recorded as an OBSERVATION
          # (#4337) — a preview enumerates what an apply would rewrite, and
          # `dry_run` defaults to TRUE here, so this is the path an operator
          # normally takes first.
          if @dry_run
            record_preview_event(org_extid, mode, outcome[:status], before, outcome[:reason])
            return build(outcome[:status], org_extid, mode, before, nil, outcome[:reason])
          end

          # A Stripe failure also wrote nothing, so there is no after-snapshot —
          # but the operator DID attempt the mutation and Stripe refused it, so
          # the attempt is recorded (result: :failure, derived from OK_STATUSES).
          if outcome[:status] == :stripe_error
            record_audit_event(org_extid, mode, outcome[:status], before, nil, outcome[:reason])
            return build(outcome[:status], org_extid, mode, before, nil, outcome[:reason])
          end

          # Reload so the after-snapshot reflects the freshly-written fields.
          @org  = Onetime::Organization.load(@org.objid) || @org
          after = snapshot(@org)

          record_audit_event(org_extid, mode, outcome[:status], before, after, outcome[:reason])

          build(
            outcome[:status],
            org_extid,
            mode,
            before,
            after,
            outcome[:reason],
            memberships: outcome[:memberships],
          )
        end

        private

        # Standalone (billing disabled) is decided FIRST — before the
        # stripe_subscription_id check — so a leftover subscription id on a
        # self-hosted install cannot route reconcile to Stripe. Memoized because
        # both `resolve_mode` and `dispatch` ask, and `billing_enabled?` reads a
        # config singleton.
        #
        # @return [Boolean]
        def standalone?
          return @standalone unless @standalone.nil?

          # WithEntitlements#billing_enabled? already rescues to false, so a
          # broken BillingConfig degrades to standalone rather than raising —
          # the same polarity as every other read of this predicate.
          @standalone = !@org.billing_enabled?
        end

        # @return [String] MODE_STRIPE_SYNC or MODE_ENTITLEMENTS_ONLY. Standalone
        #   reports MODE_ENTITLEMENTS_ONLY on purpose — see the WIRE NOTE in the
        #   class docs (the mode string is a closed zod enum on the admin UI).
        def resolve_mode
          return MODE_ENTITLEMENTS_ONLY if standalone?

          @org.stripe_subscription_id.to_s.empty? ? MODE_ENTITLEMENTS_ONLY : MODE_STRIPE_SYNC
        end

        def dispatch(mode)
          if standalone?
            reconcile_standalone
          elsif mode == MODE_STRIPE_SYNC
            reconcile_from_stripe(@org.stripe_subscription_id.to_s)
          else
            reconcile_entitlements_only
          end
        rescue ::Stripe::StripeError => ex
          # A refusal returns a status; it does not raise out of the op. The
          # colonel adapter converts this back into its 4xx form error so the
          # HTTP contract is unchanged.
          #
          # KNOWN GAP, deliberate: only StripeError is contained. On the
          # stripe_sync path the engine materializes with raise_on_miss: true,
          # so a subscription whose resolved plan is missing from cache AND
          # config raises ::Billing::PlanCacheMissError out of this op — after
          # the billing fields were applied. That parity with the webhook path
          # (which relies on the raise for retry/observability) predates this
          # op; containing it here would need its own status + wire vocabulary.
          # Revisit with the D12 preview work (#3907 item 4).
          { status: :stripe_error, reason: ex.message }
        end

        def reconcile_from_stripe(subscription_id)
          # ApplySubscriptionToOrg.call has NO dry_run parameter, so a preview
          # cannot exercise the engine. Report the mode and mutate nothing
          # rather than fabricating an "after" from a second, independently
          # derived plan lookup that an apply could disagree with.
          if @dry_run
            return {
              status: :planned,
              reason: "Would re-pull Stripe subscription #{subscription_id} and re-apply it",
            }
          end

          subscription = ::Stripe::Subscription.retrieve(
            id: subscription_id,
            expand: ['items.data.price.product'],
          )

          # Instance form (not .call) so the engine's MaterializeResult — and
          # the membership-cascade counts riding on it (#3907 item 3) — can be
          # read back without changing .call's Boolean return contract for the
          # webhook callers.
          engine = ::Billing::Operations::ApplySubscriptionToOrg.new(@org, subscription, owner: true)
          engine.call

          {
            status: :applied,
            reason: nil,
            memberships: engine.materialize_result&.memberships,
          }
        end

        def reconcile_entitlements_only
          # The engine already implements dry_run (-> :would_materialize) and
          # still reports :skipped_no_plan / :plan_not_found ahead of that check,
          # so a preview reports the real blocking condition.
          #
          # skip_if_fresh stays at its default (false) on purpose: grant/revoke
          # do NOT stamp materialized_entitlements_at, so a freshness check is
          # blind to override-induced drift and would skip the repair.
          result = ::Billing::Operations::ApplySubscriptionToOrg
            .materialize_entitlements_for_org(@org, dry_run: @dry_run)

          {
            status: result.status,
            reason: entitlements_only_reason(result),
            # nil on every status but :materialized (the engine populates it
            # only where its cascade ran — #3907 item 3).
            memberships: result.memberships,
          }
        end

        # The engine hardcodes `reason: nil` on :would_materialize
        # (apply_subscription_to_org.rb, would_materialize_result), which left
        # a dry run with nothing human-readable to print — adapters showed a
        # bare status. Synthesize a reason from the MaterializeResult's planid
        # + entitlements_count, which the op otherwise discards. `reason` stays
        # the human-readable carrier for THIS (a dry-run preview has no
        # structured shape worth a field); the cascade counts are the one thing
        # that graduated to a structured field ({Result#memberships}, #3907).
        # Every other status passes the engine reason through byte-identical.
        def entitlements_only_reason(result)
          return result.reason unless result.status == :would_materialize && result.reason.nil?

          "Would materialize #{result.entitlements_count} entitlements " \
            "for plan #{result.planid}"
        end

        # Billing-disabled (self-hosted) reconcile — D13.
        #
        # The plan engine is NOT reachable here: `materialize_entitlements_for_org`
        # keys off `planid`, and a standalone org's canonical set is
        # STANDALONE_ENTITLEMENTS regardless of what `planid` happens to hold.
        # Delegating to `materialize_standalone_entitlements!` is what makes the
        # materialized set agree with the runtime fail-open at
        # `WithPlanEntitlements#entitlements`.
        #
        # The cascade is EXPLICIT here. `materialize_standalone_entitlements!`
        # writes the org's sets only — unlike the plan engine's
        # `execute_materialize`, it does NOT re-materialize memberships. Without
        # the second call every member keeps a stale `org ∩ ROLE_ENTITLEMENTS`
        # intersection and the reconcile is half-done. (Same pairing as the
        # `materialize_standalone_entitlements` chore.)
        def reconcile_standalone
          if @dry_run
            return {
              status: :planned,
              reason: 'Billing disabled: would materialize STANDALONE_ENTITLEMENTS ' \
                      'and re-materialize every active membership',
            }
          end

          # Best-effort, matching the plan engine: `execute_materialize` also
          # ignores the materializer's return and reports on the resulting set.
          # The before/after `materialized_count` diff is what shows the operator
          # whether anything landed; a falsey return is worth a log line, not a
          # bespoke failure status.
          unless @org.materialize_standalone_entitlements!
            OT.le '[org-reconcile] standalone materialization returned falsey',
              org_extid: @org.extid
          end

          cascade = cascade_to_memberships

          { status: :standalone, reason: standalone_reason(cascade), memberships: cascade }
        end

        # Membership re-materialization is DEGRADABLE: the org-level write has
        # already committed, and `OrganizationMembership#entitlements` falls back
        # to computing the intersection on the fly. Swallow and log rather than
        # abort — the same posture as `execute_materialize` and the chore.
        #
        # @return [Hash, nil] rematerialize_all_memberships! result, or nil if it raised
        def cascade_to_memberships
          result = @org.rematerialize_all_memberships!

          if result[:failed].to_i.positive?
            OT.le '[org-reconcile] membership re-materialization had failures',
              org_extid: @org.extid,
              memberships_total: result[:total],
              memberships_failed: result[:failed],
              memberships_failed_ids: result[:failed_ids]
          end

          result
        rescue StandardError => ex
          OT.le '[org-reconcile] membership re-materialization raised',
            exception: ex,
            org_extid: @org.extid
          nil
        end

        # The counts ALSO ride on {Result#memberships} since #3907 item 3; the
        # sentence here stays because `reason` is what the CLI text path and
        # the admin UI print without any extra rendering.
        def standalone_reason(cascade)
          base = 'Billing disabled: materialized STANDALONE_ENTITLEMENTS'
          return "#{base}; membership cascade failed (see logs)" if cascade.nil?

          "#{base}; memberships re-materialized #{cascade[:success]}/#{cascade[:total]}"
        end

        # Billing snapshot. Shape is BYTE-IDENTICAL to the pre-extraction
        # ReconcileOrganization#snapshot_state — the colonel emits it verbatim as
        # before/after and src/schemas/api/internal/responses/colonel-organizations.ts
        # (colonelReconcileSnapshotSchema) + AdminOrganizationDetail.vue consume it.
        def snapshot(org)
          {
            planid: org.planid,
            subscription_status: org.subscription_status,
            subscription_period_end: org.subscription_period_end,
            materialized_count: org.materialized_entitlements.size,
          }
        end

        # One audit event per applied reconcile (CONTRACT 4 / epic D4).
        # actor/target are PUBLIC ids; the before/after billing diff is captured
        # in detail so the trail records what the reconcile actually changed.
        #
        # `result:` is derived from OK_STATUSES, never pinned — see the class
        # docs. `reason` is only included when the engine supplied one, so the
        # success-path detail shape is unchanged.
        def record_audit_event(org_extid, mode, status, before, after, reason = nil)
          detail          = { mode: mode, status: status.to_s, before: before, after: after }
          detail[:reason] = reason.to_s unless reason.to_s.empty?

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: org_extid,
            result: OK_STATUSES.include?(status) ? :success : :failure,
            detail: detail,
          )
        end

        # One OBSERVATION per dry run (#4337), on the budgeted access trail —
        # never the operator trail, which stays a record of things that
        # actually happened. Same verb and target as the applied event so a
        # reader can line a preview up against the apply that followed it;
        # `result: 'preview'` and `dry_run: true` are what tell them apart.
        #
        # No after-snapshot: nothing was written, and a projected one would be
        # a re-derivation that can disagree with an apply (see Result#after).
        def record_preview_event(org_extid, mode, status, before, reason = nil)
          detail          = { dry_run: true, mode: mode, status: status.to_s, before: before }
          detail[:reason] = reason.to_s unless reason.to_s.empty?

          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: org_extid,
            result: 'preview',
            detail: detail,
          )
        end

        def build(status, org_extid, mode, before, after, reason, memberships: nil)
          Result.new(
            status: status,
            org_id: org_extid,
            mode: mode,
            before: before,
            after: after,
            reason: reason,
            memberships: memberships,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end

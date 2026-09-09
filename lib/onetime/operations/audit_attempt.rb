# lib/onetime/operations/audit_attempt.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Operations
    # AuditAttempt — the ENVELOPE for the two #4337 row families, in one place.
    #
    # #4337 established that an operator action which changed nothing still
    # records, and that the two ways of changing nothing go to DIFFERENT trails:
    #
    #   * A NO-CHANGE ATTEMPT is a live firing of a mutating verb that found
    #     nothing to move (suspend on an already-suspended customer, purge on an
    #     already-empty queue). The operator got past every confirmation gate and
    #     pulled the trigger; whether the state happened to already match must
    #     not decide whether the trail shows the attempt. It belongs on the
    #     OPERATOR trail ({Onetime::ColonelAuditEvent.record}), under the same
    #     verb and target as the applied event, marked `outcome: 'no_change'`.
    #
    #   * A DRY-RUN PREVIEW changed nothing because it was never going to. It is
    #     reconnaissance — "show me what deleting this org would take out" — and
    #     it belongs on the budgeted OBSERVATION trail
    #     ({Onetime::ColonelAuditEvent.record_access}), under the same verb and
    #     target, with `result: 'preview'` and `dry_run: true`.
    #
    # Before this module each op re-typed that envelope by hand, and the
    # correctness of the whole feature rested on ~28 hand-written kwarg lists
    # agreeing with one another. The five kwargs were never the problem; three
    # marker fields enforced only by CONVENTION were:
    #
    #   1. `result:` — `:success` on the operator trail vs `'preview'` on the
    #      observation trail. Get it wrong and a preview reads as an applied
    #      change, or an attempt disappears from the applied-verb view.
    #   2. `outcome: 'no_change'` — the marker every verb-filter query and every
    #      reviewer's mental model depends on to tell an attempt from an effect.
    #   3. The ABSENCE of `fail_closed:`. A no-change destroyed nothing, so there
    #      is no irrecoverable fact for a hard failure to protect; hard-failing
    #      an idempotent no-op would turn a harmless double-click into an
    #      operator-visible error. See the fail-closed contract in #4333.
    #
    # This module makes all three structural rather than remembered. There is no
    # `fail_closed` parameter to pass, the trail is chosen by which method you
    # call, and the marker is merged LAST so a call site cannot displace it.
    #
    # ## What stays at the call site
    #
    # The DETAIL, and the per-op security rationale comment above the branch that
    # decides to emit. That comment is genuinely per-op — why THIS verb's
    # no-change is worth a row, why THESE fields and not others — and it is the
    # most valuable text in the file. Nothing here replaces it. This module owns
    # only the parts that must be identical across every op.
    #
    # ## Sibling of {Onetime::AuditReason}, not an extension of it
    #
    # Reason policy has real per-op variance the envelope does not: the
    # suspension op keeps `reason:` present unconditionally on SUSPEND but
    # omit-when-absent on UNSUSPEND, so a module that auto-merged the reason
    # would break that shape. The two concerns compose at the call site instead:
    #
    #   record_no_change_attempt(with_reason(purged: 0))
    #
    # ## Naming
    #
    # Deliberately NOT `record_no_change_event` / `record_preview_event`: many
    # ops already define methods by those names, with varying arity, and a module
    # method of the same name would be silently shadowed by the class body. Each
    # op keeps its own named wrapper (and that wrapper's comment) and delegates.
    #
    # ## Usage
    #
    #   class Purge
    #     include Onetime::AuditReason
    #     include Onetime::Operations::AuditAttempt
    #
    #     AUDIT_VERB = 'queue.dlq.purge'
    #
    #     private
    #
    #     # `audit_verb` defaults to AUDIT_VERB; `audit_actor` to @actor.
    #     def audit_target = @queue
    #
    #     def record_preview_event(count)
    #       record_preview_observation(with_reason(count: count))
    #     end
    #
    #     def record_no_change_event
    #       record_no_change_attempt(with_reason(purged: 0))
    #     end
    #   end
    #
    module AuditAttempt
      # The `outcome` value that marks an operator-trail row as an attempt that
      # moved nothing. Verb-filter queries and the audit screen both key off it,
      # so it lives here rather than being retyped as a literal per op.
      NO_CHANGE_OUTCOME = 'no_change'

      # The `result` value that marks an observation-trail row as a dry run.
      # A String, not a Symbol, matching {Onetime::ColonelAuditEvent.record_access}'s
      # documented `'preview'` and the shape already on the wire.
      PREVIEW_RESULT = 'preview'

      private

      # Record a mutation ATTEMPT that moved nothing, on the OPERATOR trail.
      #
      # There is deliberately NO `fail_closed` parameter. A no-change attempt
      # destroyed nothing, so there is no irrecoverable fact a hard failure could
      # surface — all it could do is fail an operation that was already a no-op.
      # Ops that need fail-closed writes are recording an APPLIED effect and call
      # {Onetime::ColonelAuditEvent.record} directly, as they did before.
      #
      # @param detail [Hash, nil] the op's own context. Merged UNDER the
      #   `outcome` marker, so a call site cannot displace it.
      # @return [Hash, nil] the stored event, or nil if the write failed
      #   (`record` is best-effort by default — see `errors.rb`).
      def record_no_change_attempt(detail = {})
        Onetime::ColonelAuditEvent.record(
          actor: audit_actor,
          verb: audit_verb,
          target: audit_target,
          result: :success,
          detail: (detail || {}).merge(outcome: NO_CHANGE_OUTCOME),
        )
      end

      # Record a dry-run PREVIEW, on the budgeted OBSERVATION trail.
      #
      # Never the operator trail: a preview applied nothing, and putting
      # reconnaissance among applied effects is exactly the conflation #4337
      # exists to prevent. `record_access` has no `fail_closed` keyword at all —
      # observing must never break the console.
      #
      # @param detail [Hash, nil] the op's own context. Merged UNDER the
      #   `dry_run` marker, so a call site cannot displace it.
      # @return [Hash, nil] the stored event, or nil if the write failed.
      def record_preview_observation(detail = {})
        Onetime::ColonelAuditEvent.record_access(
          actor: audit_actor,
          verb: audit_verb,
          target: audit_target,
          result: PREVIEW_RESULT,
          detail: (detail || {}).merge(dry_run: true),
        )
      end

      # The acting colonel's public identity. Every op in the cohort stores it in
      # `@actor`; override when yours does not.
      def audit_actor
        @actor
      end

      # The verb both rows carry — the SAME verb as the applied event, which is
      # what lets a preview, an attempt and an effect read as one sequence.
      #
      # Defaults to the class's `AUDIT_VERB`. Ops whose verb is direction- or
      # action-dependent override this; several already define a method by
      # exactly this name, and a class-body definition wins over an included
      # module's, so those keep working untouched.
      def audit_verb
        self.class::AUDIT_VERB
      end

      # The public id of the affected resource. No sensible default — an op that
      # includes this module and forgets it should fail loudly at the first
      # emit, not record a row against nil.
      def audit_target
        raise NotImplementedError, "#{self.class} must define #audit_target"
      end
    end
  end
end

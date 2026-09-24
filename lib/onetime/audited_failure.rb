# lib/onetime/audited_failure.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  # AuditedFailure — the failure half of the mutating-admin-op audit contract.
  #
  # {Onetime::ColonelAuditEvent} is the single write path for mutating admin
  # operations, but every incumbent call site sits INSIDE the success path,
  # AFTER the mutation. When an op raises (privilege guard, precondition,
  # validation, unexpected error) the `record` line never executes, so the
  # trail shows only what worked. Passing `result: :failure` at those call
  # sites changes nothing — they do not run. Failure auditing is structural,
  # not an argument.
  #
  # This module supplies that structure as a declarative class macro. It wraps
  # the op's entry method with a `prepend`ed rescue that records ONE
  # `result: :failure` event and re-raises the original exception unchanged, so
  # callers, control flow, and HTTP status mapping are untouched.
  #
  # @example An operation (entry method #call)
  #   class Purge
  #     include Onetime::AuditedFailure
  #     audit_failures :call, verb: 'customer.purge', target: -> { @customer&.extid }
  #
  #     def call
  #       ... # unchanged; still records its own result: :success event
  #     end
  #   end
  #
  # @example A colonel Logic class (entry method #process)
  #   class DeleteSecret < ColonelAPI::Logic::Base
  #     include Onetime::AuditedFailure
  #     audit_failures :process, verb: AUDIT_VERB, target: -> { @secret&.shortid }
  #   end
  #
  # ## Two hierarchies, one mechanism
  #
  # `Onetime::Operations::*` / `Auth::Operations::*` (entry `#call`) and
  # `ColonelAPI::Logic::Base` subclasses (entry `#process`) are unrelated class
  # trees. The macro takes the entry method name, so the same mechanism covers
  # both: ops (which the CLI also drives) and the handful of colonel Logic
  # classes that mutate inline without an op behind them.
  #
  # It is deliberately OPT-IN per class rather than a base-class wrapper: most
  # colonel Logic classes are reads, and reads must never write an audit event
  # (CONTRACT 4). An automatic wrapper on `ColonelAPI::Logic::Base` would start
  # emitting failure events for `GET /users`, `GET /secrets`, and friends.
  #
  # ## Authorization rejections are NEVER recorded
  #
  # The audit set is capped by COUNT with no TTL, so anything an unauthorized
  # caller can trigger a write with is a log-eviction primitive: 10k rejected
  # requests would flush the entire real destructive-action trail. Two controls
  # keep that closed:
  #
  # 1. Structural — for Logic classes the macro wraps `#process`, and Otto runs
  #    `#raise_concerns` (where `verify_one_of_roles!` lives) BEFORE it. An
  #    authorization rejection therefore never reaches the wrapper. Otto also
  #    enforces `role=colonel` at the routing layer ahead of both.
  # 2. Defense-in-depth — {authorization_rejection?} drops `Onetime::Forbidden`
  #    / `Onetime::Unauthorized` / Otto authorization errors even if one is
  #    somehow raised from inside the wrapped method.
  #
  # Everything else post-authorization IS recorded: privilege guards
  # (SetSuspension::PrivilegedAccount), not-found, validation/precondition
  # errors, and unexpected StandardErrors.
  #
  # ## Nesting records once (innermost wins)
  #
  # An op may call another audited op. The exception instance is tagged the
  # first time a failure is recorded for it, so an outer wrapper re-raising the
  # same exception does not write a second event. The innermost audited frame —
  # the one closest to the actual failure — owns the record. That holds for the
  # swapped verb below too: the tag goes on the exception, not on the verb, so
  # an inner frame that recorded `audit.write_failure` still suppresses the
  # outer frame rather than letting it re-report the same raise under the outer
  # op's verb.
  #
  # ## ONE exception class is special-cased: Onetime::AuditWriteFailure
  #
  # Everything else here is verb-preserving — the failure event carries the
  # byte-identical verb the success path would have written. There is exactly
  # one exception, and it exists because the general rule produces an
  # affirmatively WRONG record for it.
  #
  # Every fail-closed call site (#4333) sits inside a wrapper: they record
  # AFTER mutating, with `fail_closed: true`, and a failed write raises
  # {Onetime::AuditWriteFailure} out of the op (Customers::Impersonate alone
  # unwinds its session-only mutation first; the rest cannot). Recording that
  # raise under the
  # op's own verb would say `customer.purge / result: :failure` — for a purge
  # that DESTROYED THE ACCOUNT and then could not write its receipt. Worse, the
  # follow-up write is fail-open and lands on a later tick, so a transient
  # datastore blip typically lets it SUCCEED: the only stored event for the
  # action would be an affirmative claim that it failed. Anyone reconciling
  # "did this account get deleted?" gets a wrong answer, not a missing one.
  #
  # So an AuditWriteFailure is recorded under {AUDIT_WRITE_FAILURE_VERB}
  # instead, at the ORIGINAL target, with the original verb in the detail as
  # `failed_verb`. The record then says what is true — "the trail is missing an
  # event for customer.purge on ur_abc" — and does not claim an outcome for the
  # action itself.
  #
  # ## Best-effort, like the model it writes to
  #
  # Nothing in this path may break the operation it wraps. Resolving verb /
  # target / actor is rescued, the record call is rescued, and
  # {ColonelAuditEvent.record} swallows its own errors. The original exception is
  # always re-raised.
  module AuditedFailure
    # Marker set on an exception instance once a failure event has been written
    # for it. Per-raise state, so it is inherently thread-safe.
    RECORDED_FLAG = :@onetime_audited_failure_recorded

    # Fallback when verb/target/actor cannot be resolved at failure time (e.g.
    # the op raised before assigning the ivar the lambda reads).
    UNKNOWN = 'unknown'

    # Verb for the one special-cased exception class (see the class docs): the
    # wrapped op raised because its OWN audit write failed, so this event
    # reports a HOLE IN THE TRAIL, not an outcome for the operation.
    #
    # The constant lives here, not on {Onetime::ColonelAuditEvent}, per the
    # repo's verb-ownership rule (see ColonelAuditEvent::VERB_COLONEL_SIGNIN):
    # a verb is single-sourced on the model only when it has SEVERAL emitters
    # that share nothing else. This one has exactly one emitter — this module —
    # so it belongs to this module.
    #
    # A NEW leading category, deliberately, rather than a dotted child of the
    # verb that failed. {Onetime::ColonelAuditReader} matches a verb exactly or
    # as a dotted PREFIX, so spelling it `customer.purge.write_failure` would
    # fold these back under the `customer.purge` filter and re-create at read
    # time exactly the confusion the swap removes. Under `audit.*` they are
    # separately filterable, and `audit` rolls up any future sibling.
    #
    # The admin console needs no change to show it: VERB_CATEGORIES in
    # ColonelAuditLog.vue is a superset-tolerant convenience menu, not an
    # allowlist, so an uncategorised verb still lists under "All" and the
    # server validates nothing against that list.
    AUDIT_WRITE_FAILURE_VERB = 'audit.write_failure'

    class << self
      def included(base)
        base.extend(ClassMethods)
      end

      # Bare authorization/authentication rejections, which must never write.
      # Resolved lazily by `defined?` so this file carries no load-order
      # dependency on the error classes or on Otto being loaded.
      #
      # Onetime::Forbidden covers Onetime::LimitExceeded by inheritance, so no
      # throttle rejection is auto-audited through this path either — which is
      # the point: the OPERATOR trail (`events`) is count-capped with no TTL, so
      # anything an unauthorized caller can trigger a write into it with is a
      # log-eviction primitive. This predicate is the automatic half of that
      # invariant.
      #
      # A call site that genuinely needs to record an event an UNAUTHENTICATED
      # caller can cause must write it through
      # {Onetime::ColonelAuditEvent.record_security}, which lands in the separate
      # `security_events` collection with its own count cap and age bound — NOT
      # through `.record`. Bounding the write RATE is not an accepted substitute
      # (see the WRITE-FREQUENCY INVARIANT on {Onetime::ColonelAuditEvent}): the
      # one such writer today, the reset-request throttle, still rate-limits
      # itself, but for signal quality only.
      #
      # @param error [Exception]
      # @return [Boolean]
      def authorization_rejection?(error)
        return true if defined?(Onetime::Forbidden) && error.is_a?(Onetime::Forbidden)
        return true if defined?(Onetime::Unauthorized) && error.is_a?(Onetime::Unauthorized)
        return true if defined?(Otto::Security::AuthorizationError) &&
                       error.is_a?(Otto::Security::AuthorizationError)

        false
      end

      # Write exactly one `result: :failure` event for `error`, unless it is an
      # authorization rejection or already recorded by an inner audited frame.
      #
      # @param extra [Hash, nil] op-supplied context merged into the detail (see
      #   the `detail:` macro argument). `error`/`message` always win.
      # @return [Hash, nil] the stored event, or nil when skipped/failed.
      def record(actor:, verb:, target:, error:, extra: nil)
        return nil if authorization_rejection?(error)
        return nil if error.instance_variable_defined?(RECORDED_FLAG)

        error.instance_variable_set(RECORDED_FLAG, true)

        verb, target, extra = write_failure_context(error, verb: verb, target: target, extra: extra)

        # NEVER `fail_closed:` here, on either path. This write is the fail-open
        # half of the contract by design, and for the swapped verb it is also
        # the recursion guard: opting the report of a failed write into the
        # raising path would hand this same wrapper a second AuditWriteFailure
        # to chase (the RECORDED_FLAG on the FIRST error would not stop it — a
        # fresh raise is a fresh, untagged instance).
        Onetime::ColonelAuditEvent.record(
          actor: actor,
          verb: verb,
          target: target,
          result: :failure,
          detail: failure_detail(error, extra),
        )
      rescue StandardError => ex
        # Never let failure-auditing bookkeeping mask the original error.
        OT.le('[AuditedFailure] record failed', exception: ex, verb: verb.to_s)
        nil
      end

      # Is this the wrapped op reporting that its OWN audit write failed?
      # Resolved lazily by `defined?` for the same reason
      # {authorization_rejection?} is: no load-order dependency on the error
      # classes from this file.
      #
      # @param error [Exception]
      # @return [Boolean]
      def audit_write_failure?(error)
        return false unless defined?(Onetime::AuditWriteFailure)

        error.is_a?(Onetime::AuditWriteFailure)
      end

      # Apply the one exception-class special case (see the class docs): an
      # {Onetime::AuditWriteFailure} is recorded under
      # {AUDIT_WRITE_FAILURE_VERB} rather than under the op's own verb.
      #
      # The error carries the verb and target of the write that failed, which
      # is the more precise pair: an op can fail-closed on a write whose verb
      # is not the wrapper's own (a nested audited call), and the event should
      # name the trail entry that is actually missing. Both fall back to the
      # wrapper's resolved values when the error carries a blank one, so this
      # can never downgrade a good target to an empty string.
      #
      # `failed_verb`, NOT `reason` — since #4338 `reason` in an audit detail
      # means operator-supplied justification, and this is machine context.
      #
      # @return [Array(String, String, Hash, nil)] verb, target, extra
      def write_failure_context(error, verb:, target:, extra:)
        return [verb, target, extra] unless audit_write_failure?(error)

        failed_verb   = error.verb.to_s.empty? ? verb : error.verb.to_s
        failed_target = error.target.to_s.empty? ? target : error.target.to_s

        [AUDIT_WRITE_FAILURE_VERB, failed_target, (extra || {}).merge(failed_verb: failed_verb)]
      end

      # Error class + message, plus whatever context the op declared. The
      # message may embed operator-supplied text, so it still passes through
      # ColonelAuditEvent's redaction and length bounds on the way to storage.
      # Op-supplied keys are merged UNDER error/message so they can never
      # displace the failure's own identity.
      def failure_detail(error, extra = nil)
        base = { error: error.class.name, message: error.message.to_s }
        return base unless extra.is_a?(Hash) && !extra.empty?

        extra.merge(base)
      end

      # Resolve the op-supplied `detail:` lambda. Anything that is not a Hash
      # (or that raises) is dropped — extra context is never worth risking the
      # event itself.
      def resolve_detail(receiver, spec)
        return nil if spec.nil?

        value = spec.is_a?(Proc) ? receiver.instance_exec(&spec) : spec
        value.is_a?(Hash) ? value : nil
      rescue StandardError
        nil
      end

      # Resolve a verb/target argument that is either a literal or a lambda
      # evaluated against the failing instance. Stringified here so an
      # unresolvable value lands as UNKNOWN rather than an empty target.
      def resolve(receiver, spec)
        value = spec.is_a?(Proc) ? receiver.instance_exec(&spec) : spec
        value = value.to_s
        value.empty? ? UNKNOWN : value
      rescue StandardError
        UNKNOWN
      end

      # Resolve the actor WITHOUT stringifying: `@actor` is sometimes a
      # Customer-like object, and `to_s` on one can yield an internal objid.
      # ColonelAuditEvent.normalize_actor owns the extid/email extraction — hand
      # it the raw value and let the single write path do its job.
      def resolve_actor(receiver, spec)
        spec.is_a?(Proc) ? receiver.instance_exec(&spec) : spec
      rescue StandardError
        nil
      end
    end

    module ClassMethods
      # Record a `result: :failure` audit event when `method_name` raises, then
      # re-raise unchanged.
      #
      # @param method_name [Symbol] the mutation entry point (`:call` for
      #   Operations, `:process` for colonel Logic classes).
      # @param verb [String, Symbol, Proc] audit verb, or a lambda evaluated
      #   against the instance when the verb depends on state (e.g. suspend vs
      #   unsuspend). MUST match the verb the success path records — with the
      #   one exception the module owns rather than the call site: an
      #   {Onetime::AuditWriteFailure} is recorded under
      #   {AUDIT_WRITE_FAILURE_VERB} instead (see the class docs).
      # @param target [String, Symbol, Proc] PUBLIC id of the affected resource
      #   (extid / shortid / queue name). Never an internal objid.
      # @param actor [String, Proc] acting colonel's PUBLIC identity. Defaults
      #   to the `@actor` convention every audited op already follows.
      # @param detail [Hash, Proc, nil] optional extra context merged into the
      #   failure detail. Needed where a failure is otherwise ambiguous — an op
      #   with a dry-run mode records success only on the applied path, so
      #   without `dry_run` in the detail an operator cannot tell a blown-up
      #   preview from a blown-up mutation. Same rules as any audit detail:
      #   PUBLIC ids only, never secret content.
      def audit_failures(method_name = :call, verb:, target:, actor: -> { @actor }, detail: nil)
        wrapper = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
          rescue StandardError => ex
            Onetime::AuditedFailure.record(
              actor: Onetime::AuditedFailure.resolve_actor(self, actor),
              verb: Onetime::AuditedFailure.resolve(self, verb),
              target: Onetime::AuditedFailure.resolve(self, target),
              error: ex,
              extra: Onetime::AuditedFailure.resolve_detail(self, detail),
            )
            raise
          end
        end

        prepend wrapper
      end
    end
  end
end

# lib/onetime/audited_failure.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'

module Onetime
  # AuditedFailure — the failure half of the mutating-admin-op audit contract.
  #
  # {Onetime::AdminAuditEvent} is the single write path for mutating admin
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
  # the one closest to the actual failure — owns the record.
  #
  # ## Best-effort, like the model it writes to
  #
  # Nothing in this path may break the operation it wraps. Resolving verb /
  # target / actor is rescued, the record call is rescued, and
  # {AdminAuditEvent.record} swallows its own errors. The original exception is
  # always re-raised.
  module AuditedFailure
    # Marker set on an exception instance once a failure event has been written
    # for it. Per-raise state, so it is inherently thread-safe.
    RECORDED_FLAG = :@onetime_audited_failure_recorded

    # Fallback when verb/target/actor cannot be resolved at failure time (e.g.
    # the op raised before assigning the ivar the lambda reads).
    UNKNOWN = 'unknown'

    class << self
      def included(base)
        base.extend(ClassMethods)
      end

      # Bare authorization/authentication rejections, which must never write.
      # Resolved lazily by `defined?` so this file carries no load-order
      # dependency on the error classes or on Otto being loaded.
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
      # @return [Hash, nil] the stored event, or nil when skipped/failed.
      def record(actor:, verb:, target:, error:)
        return nil if authorization_rejection?(error)
        return nil if error.instance_variable_defined?(RECORDED_FLAG)

        error.instance_variable_set(RECORDED_FLAG, true)

        Onetime::AdminAuditEvent.record(
          actor: actor,
          verb: verb,
          target: target,
          result: :failure,
          detail: failure_detail(error),
        )
      rescue StandardError => ex
        # Never let failure-auditing bookkeeping mask the original error.
        OT.le('[AuditedFailure] record failed', exception: ex, verb: verb.to_s)
        nil
      end

      # Error class + message only. The message may embed operator-supplied
      # text, so it still passes through AdminAuditEvent's redaction and length
      # bounds on the way to storage.
      def failure_detail(error)
        { error: error.class.name, message: error.message.to_s }
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
      # AdminAuditEvent.normalize_actor owns the extid/email extraction — hand
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
      #   unsuspend). MUST match the verb the success path records.
      # @param target [String, Symbol, Proc] PUBLIC id of the affected resource
      #   (extid / shortid / queue name). Never an internal objid.
      # @param actor [String, Proc] acting colonel's PUBLIC identity. Defaults
      #   to the `@actor` convention every audited op already follows.
      def audit_failures(method_name = :call, verb:, target:, actor: -> { @actor })
        wrapper = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            super(*args, **kwargs, &block)
          rescue StandardError => ex
            Onetime::AuditedFailure.record(
              actor: Onetime::AuditedFailure.resolve_actor(self, actor),
              verb: Onetime::AuditedFailure.resolve(self, verb),
              target: Onetime::AuditedFailure.resolve(self, target),
              error: ex,
            )
            raise
          end
        end

        prepend wrapper
      end
    end
  end
end

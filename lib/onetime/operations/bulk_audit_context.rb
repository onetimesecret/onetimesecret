# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Operations
    # Receipt-backed capability for suppressing per-item audit events inside one
    # bounded bulk operation. Candidate targets are registered before mutation,
    # consumed once, and narrowed to the exact parent and child operations found
    # by that candidate's preflight.
    class BulkAuditContext
      class CandidateAuthorization
        private_class_method :new, :allocate

        def initialize(context:, actor:, covered_verbs:, operations:)
          @context       = context
          @actor         = actor
          @covered_verbs = covered_verbs
          @operations    = operations.to_h { |operation| [operation_key(**operation), nil] }
        end

        def verified_for?(actor:, verb:, target:, scope:, operation:)
          return false unless @context.active?
          return false unless @actor == actor.to_s && @covered_verbs.include?(verb.to_s)

          key = operation_key(verb: verb, target: target, scope: scope)
          return false unless @operations.key?(key)

          owner = @operations[key]
          return false if owner && !owner.equal?(operation)

          @operations[key] ||= operation
          true
        end

        private

        def operation_key(verb:, target:, scope: nil)
          [verb.to_s, target.to_s, scope.to_s]
        end
      end

      def self.verified?(authorization, actor:, verb:, target:, operation:, scope: nil)
        authorization.instance_of?(CandidateAuthorization) &&
          authorization.verified_for?(
            actor: actor,
            verb: verb,
            target: target,
            scope: scope,
            operation: operation,
          )
      end

      def self.start!(actor:, verb:, target:, covered_verbs:, candidate_targets:, detail:)
        receipt = Onetime::ColonelAuditEvent.record(
          actor: actor,
          verb: verb,
          target: target,
          result: :started,
          detail: detail,
          fail_closed: true,
        )
        raise Onetime::AuditWriteFailure.new(verb: verb, target: target) unless receipt.is_a?(Hash) && receipt['id']

        new(
          actor: actor,
          verb: verb,
          target: target,
          covered_verbs: covered_verbs,
          candidate_targets: candidate_targets,
          receipt_id: receipt.fetch('id'),
        )
      end

      def active?
        @state == :active && !@receipt_id.empty?
      end

      def authorize_candidate(customer_target:, operations:)
        return nil unless active?

        target = customer_target.to_s
        return nil unless @candidate_targets[target] == :available

        @candidate_targets[target] = :consumed
        CandidateAuthorization.__send__(
          :new,
          context: self,
          actor: @actor,
          covered_verbs: @covered_verbs,
          operations: operations,
        )
      end

      def complete!(result:, detail:)
        finish!(state: :completed, result: result, detail: detail)
      end

      def abort!(detail:)
        finish!(state: :aborted, result: :aborted, detail: detail)
      end

      private_class_method :new, :allocate

      def initialize(actor:, verb:, target:, covered_verbs:, candidate_targets:, receipt_id:)
        @actor             = actor.to_s
        @verb              = verb.to_s
        @target            = target.to_s
        @covered_verbs     = Array(covered_verbs).map(&:to_s).freeze
        @candidate_targets = Array(candidate_targets).to_h { |candidate| [candidate.to_s, :available] }
        @receipt_id        = receipt_id.to_s
        @state             = :active
      end

      def finish!(state:, result:, detail:)
        raise ArgumentError, 'Bulk audit context is no longer active' unless active?

        # Invalidate outstanding capabilities before attempting the terminal
        # receipt so a failed completion write cannot leave suppression active.
        @state = state
        Onetime::ColonelAuditEvent.record(
          actor: @actor,
          verb: @verb,
          target: @target,
          result: result,
          detail: detail.merge(start_receipt_id: @receipt_id),
          fail_closed: true,
        )
      end
    end
  end
end

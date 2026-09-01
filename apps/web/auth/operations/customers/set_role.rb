# apps/web/auth/operations/customers/set_role.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Auth
  module Operations
    module Customers
      # Change a customer's role (colonel / admin / staff / customer).
      #
      # The ONE implementation of the role-change verb. The colonel `SetUserRole`
      # Logic class and the CLI `customers role promote/demote` command are thin
      # adapters over it. This is a MUTATING admin op, so it records exactly one
      # ColonelAuditEvent per successful change (epic #20 CONTRACT 4 / #21).
      # An idempotent no-op mutates nothing but is STILL audited, under the
      # same verb with `outcome: 'no_change'` (#4337): reaching for a role on
      # an account that already holds it is the same reach, and the trail
      # should not go quiet for it.
      #
      # `VALID_ROLES` is the single source of truth for assignable roles; the CLI
      # and colonel adapters both reference it rather than keeping their own copy.
      class SetRole
        include Onetime::LoggerMethods
        include Onetime::AuditedFailure

        AUDIT_VERB = 'customer.set_role'

        # Privilege escalation/demotion is the highest-value verb in the trail,
        # and the InvalidRole guard raises before the success-path record. A
        # rejected attempt to hand out `colonel` must be visible. Records one
        # `result: :failure` and re-raises.
        audit_failures :call, verb: AUDIT_VERB, target: -> { @customer&.extid }

        # Assignable roles, highest to lowest. This is the authoritative list;
        # adapters validate against it (do not fork a second copy).
        VALID_ROLES = %w[colonel admin staff customer].freeze

        # Raised when asked to assign a role outside VALID_ROLES. Adapters catch
        # this (CLI -> message + exit; colonel -> form error). It is also a
        # backstop: adapters should validate up front for good UX.
        class InvalidRole < StandardError; end

        # @!attribute status [r]
        #   @return [Symbol] :success (role changed) or :no_change (already at role)
        Result = Data.define(:status, :customer, :from, :to)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param role [String, Symbol] target role; must be in VALID_ROLES
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        def initialize(customer:, role:, actor:)
          @customer = customer
          @role     = role.to_s
          @actor    = actor
        end

        # @return [Result]
        # @raise [InvalidRole] when role is not assignable
        def call
          unless VALID_ROLES.include?(@role)
            raise InvalidRole, "Invalid role '#{@role}'. Valid roles: #{VALID_ROLES.join(', ')}"
          end

          from = @customer.role.to_s
          if from == @role
            record_no_change_event(from)
            return Result.new(status: :no_change, customer: @customer, from: from, to: @role)
          end

          @customer.role = @role
          @customer.save

          # One audit event per successful mutation, emitted from the op layer.
          #
          # FAIL-CLOSED (#4333): the customer row records only the role it now
          # holds, never who granted it or what it was before, so this event is
          # the only evidence a privilege grant happened. An unwritable event
          # raises Onetime::AuditWriteFailure rather than reporting :success.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { from: from, to: @role },
            fail_closed: true,
          )

          # debug level (not info): the audit event is the durable record, and an
          # info-level line here would surface in CLI stderr and break the CLI's
          # bit-for-bit output contract.
          auth_logger.debug "[customer.set_role] #{@customer.extid} #{from} -> #{@role} by #{actor_label}"
          Result.new(status: :success, customer: @customer, from: from, to: @role)
        end

        private

        # A no-change attempt (#4337) — the OPERATOR trail, not the observation
        # trail.
        #
        # Role assignment is the highest-value verb in this trail, and an
        # attempt to set `colonel` on an account that already holds it is not
        # less interesting than one that changes it — it is the same reach for
        # the same privilege. Silently dropping it meant the trail could show
        # nothing while an operator repeatedly probed a privileged account.
        #
        # Same verb and target as the applied event, with `outcome: 'no_change'`
        # marking it. NOT fail-closed: no privilege moved, so there is no
        # untraceable grant for a hard failure to surface.
        def record_no_change_event(from)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { outcome: 'no_change', from: from, to: @role },
          )
        end

        # Loggable, non-secret actor label (mirrors the audit actor normalization).
        def actor_label
          return @actor if @actor.is_a?(String)
          return @actor.extid if @actor.respond_to?(:extid) && !@actor.extid.to_s.empty?
          return @actor.email if @actor.respond_to?(:email)

          @actor.to_s
        end
      end
    end
  end
end

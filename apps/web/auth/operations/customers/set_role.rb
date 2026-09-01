# apps/web/auth/operations/customers/set_role.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/operations/customers/role_support'

module Auth
  module Operations
    module Customers
      # Change a customer's role (colonel / admin / staff / customer).
      #
      # The ONE implementation of the role-change verb. The colonel `SetUserRole`
      # Logic class and the CLI `customers role promote/demote` command are thin
      # adapters over it. This is a MUTATING admin op, so it records exactly one
      # ColonelAuditEvent per successful change (epic #20 CONTRACT 4 / #21). An
      # idempotent no-op change mutates nothing and is therefore not audited.
      #
      # `VALID_ROLES` is the single source of truth for assignable roles; the CLI
      # and colonel adapters both reference it rather than keeping their own copy.
      #
      # ## Interlocks (#4328)
      #
      # Two refusals live HERE rather than in the colonel adapter, so
      # `bin/ots customers role demote` is bound by them too:
      #
      #   :self_demotion — the acting colonel demoting their own account
      #   :last_colonel  — demoting the only remaining active colonel
      #
      # Both follow {Onetime::Operations::Memberships::Remove}'s shape: a shared
      # predicate ({RoleSupport}) so the endpoint and the CLI cannot drift into
      # different definitions of "the last one", and a single `build` exit point
      # so no early return can skip the refusal audit.
      class SetRole
        include Onetime::LoggerMethods
        include Onetime::AuditedFailure
        include Onetime::Operations::Customers::RoleSupport

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

        # Statuses that MUTATE nothing but each record one `result: :failure`
        # event. A refused privileged change is a rare, operator-driven attempt
        # worth tracing — unlike the confirmation/elevation rejections in
        # #4326/#4327, which any cookie holder can drive on demand and which
        # therefore write nothing. That distinction only holds because the
        # adapter runs these interlocks AFTER elevation and confirmation (the
        # guard-order contract in colonel/logic/destructive_action.rb); do not
        # reorder the guards without revisiting this choice.
        REFUSAL_STATUSES = [:last_colonel, :self_demotion].freeze

        # @!attribute status [r]
        #   @return [Symbol] :success (role changed), :no_change (already at
        #     role), :self_demotion or :last_colonel (refused, nothing mutated)
        Result = Data.define(:status, :customer, :from, :to)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param role [String, Symbol] target role; must be in VALID_ROLES
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param actor_objid [String, nil] the acting colonel's INTERNAL id, for
        #   the self-demotion comparison only (purge_user.rb compares the same
        #   way; the AUDIT actor stays the public id above). nil for the CLI,
        #   which has no acting customer and nothing to self-demote.
        def initialize(customer:, role:, actor:, actor_objid: nil)
          @customer    = customer
          @role        = role.to_s
          @actor       = actor
          @actor_objid = actor_objid
        end

        # @return [Result]
        # @raise [InvalidRole] when role is not assignable
        def call
          unless VALID_ROLES.include?(@role)
            raise InvalidRole, "Invalid role '#{@role}'. Valid roles: #{VALID_ROLES.join(', ')}"
          end

          @from = @customer.role.to_s
          return build(:no_change) if @from == @role

          # INTERLOCKS (#4328). Self-demotion first: it is the cheaper check and
          # the more specific answer when both apply.
          return build(:self_demotion) if self_demotion?
          return build(:last_colonel) if last_colonel?(@customer, @role)

          @customer.role = @role
          @customer.save

          # One audit event per successful mutation, emitted from the op layer.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { from: @from, to: @role },
          )

          # debug level (not info): the audit event is the durable record, and an
          # info-level line here would surface in CLI stderr and break the CLI's
          # bit-for-bit output contract.
          auth_logger.debug "[customer.set_role] #{@customer.extid} #{@from} -> #{@role} by #{actor_label}"
          build(:success)
        end

        private

        # Only a DEMOTION of one's own account is refused: a colonel raising
        # their own role is not a lockout risk, and the CLI (actor_objid nil)
        # never self-refuses.
        def self_demotion?
          return false if @actor_objid.to_s.empty?
          return false if @role == 'colonel'

          @actor_objid == @customer.objid
        end

        # Single exit point for every status, so the refusal audit cannot be
        # forgotten at an early return (Memberships::Remove#build).
        def build(status)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(status: status, customer: @customer, from: @from, to: @role)
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: { reason: status.to_s, from: @from, to: @role },
          )
        rescue StandardError => ex
          OT.le "[Customers::SetRole] refusal audit failed: #{ex.class}: #{ex.message}"
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

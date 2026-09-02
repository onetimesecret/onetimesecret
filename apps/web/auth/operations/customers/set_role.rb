# apps/web/auth/operations/customers/set_role.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/customers/role_support'

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
        include Onetime::AuditReason
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
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the audit detail of BOTH the applied event and the
        #   no-change one (never the refusal events, whose `reason` key names
        #   the refusal cause). Blank is treated as absent and the detail keeps
        #   its pre-#4338 shape; see {Onetime::AuditReason}, which also owns the
        #   255-char bound and the optional-now / required-later rollout.
        def initialize(customer:, role:, actor:, actor_objid: nil, reason: nil)
          @customer    = customer
          @role        = role.to_s
          @actor       = actor
          @actor_objid = actor_objid
          @reason      = normalize_reason(reason)
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

          # POST-WRITE re-validation (#4328). last_colonel? above is a
          # check-then-act: it is NOT atomic, so two concurrent demotions of the
          # two distinct last colonels can each pass the pre-check (each still
          # sees the other) and both write, leaving the install with zero
          # colonels — recoverable only from the CLI, the exact outcome #4328
          # exists to prevent. Re-run the roster check AFTER the write; if this
          # demotion emptied it, roll the role back and refuse through the SAME
          # build exit, so the :last_colonel failure still audits. Over-preserving
          # on a concurrent double-rollback is the safe direction.
          if demotion_left_no_colonel?
            @customer.role = @from
            @customer.save
            return build(:last_colonel)
          end

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
            detail: with_reason(from: @from, to: @role),
            fail_closed: true,
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

        # Did the just-applied write demote a colonel and leave the roster
        # empty? (#4328 post-write re-validation.) Only a demotion FROM colonel
        # can empty the roster — a promotion or an unrelated role change must
        # never be rolled back merely because the roster happens to be empty for
        # another reason, so both edges are guarded before the roster read.
        #
        # The target must also have been VERIFIED: active_colonels counts only
        # verified colonels, so demoting an UNVERIFIED colonel-role account never
        # removes anyone from the roster. Without this guard the roster is already
        # empty when no colonel is verified, and the check would roll the demotion
        # back — making a stale, never-verified (or provenance-reset) colonel role
        # impossible to remove, the same empty-roster false positive last_colonel?
        # guards against on the pre-check.
        def demotion_left_no_colonel?
          return false unless @from == 'colonel'
          return false if @role == 'colonel'
          return false unless @customer.verified?

          active_colonels.empty?
        end

        # Single exit point for every status, so neither the refusal audit nor
        # the no-change audit can be forgotten at an early return
        # (Memberships::Remove#build).
        def build(status)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)
          record_no_change_event if status == :no_change

          Result.new(status: status, customer: @customer, from: @from, to: @role)
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op. Note `reason` here is the REFUSAL CAUSE — the operator's
        # #4338 reason never rides on refusal events, so the key cannot collide.
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
        #
        # The operator's `reason` (#4338) rides here too: an attempted-but-no-op
        # action still has a why, and a probe at a privileged account is exactly
        # the row a reviewer wants the operator's own words on.
        def record_no_change_event
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: with_reason(outcome: 'no_change', from: @from, to: @role),
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

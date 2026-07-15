# apps/web/auth/operations/customers/set_plan.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # Change a customer's plan (planid).
      #
      # The ONE implementation of the plan-change verb. The colonel `UpdateUserPlan`
      # Logic class is a thin adapter over it (no CLI adapter today, but the verb
      # lives here so any future one shares the single implementation). This is a
      # MUTATING admin op, so it records exactly one AdminAuditEvent per successful
      # change (epic #20 CONTRACT 4 / #21). An idempotent no-op change mutates
      # nothing and is therefore not audited.
      #
      # Catalog validation (does `planid` exist in the billing catalog?) is the
      # adapter's job for good UX; this op treats the planid as already-validated
      # and only owns the mutation + audit, mirroring `SetRole` (whose VALID_ROLES
      # check is a backstop, not a catalog lookup this op can cheaply repeat).
      class SetPlan
        include Onetime::LoggerMethods

        # @!attribute status [r]
        #   @return [Symbol] :success (plan changed) or :no_change (already on plan)
        Result = Data.define(:status, :customer, :from, :to)

        # @param customer [Onetime::Customer] target (caller ensures non-nil,
        #   non-anonymous)
        # @param planid [String, Symbol] target plan id (caller validates against
        #   the billing catalog before calling)
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email). Never an internal objid.
        def initialize(customer:, planid:, actor:)
          @customer = customer
          @planid   = planid.to_s
          @actor    = actor
        end

        # @return [Result]
        def call
          from = @customer.planid.to_s
          return Result.new(status: :no_change, customer: @customer, from: from, to: @planid) if from == @planid

          @customer.planid = @planid
          @customer.save

          # One audit event per successful mutation, emitted from the op layer.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: 'customer.set_plan',
            target: @customer.extid,
            result: :success,
            detail: { from: from, to: @planid },
          )

          # debug level (not info): the audit event is the durable record, and an
          # info-level line here would surface in CLI stderr and break any future
          # CLI adapter's bit-for-bit output contract.
          auth_logger.debug "[customer.set_plan] #{@customer.extid} #{from} -> #{@planid} by #{actor_label}"
          Result.new(status: :success, customer: @customer, from: from, to: @planid)
        end

        private

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

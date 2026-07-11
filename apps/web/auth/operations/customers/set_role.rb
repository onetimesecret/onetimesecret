# apps/web/auth/operations/customers/set_role.rb
#
# frozen_string_literal: true

module Auth
  module Operations
    module Customers
      # Change a customer's role (colonel / admin / staff / customer).
      #
      # The ONE implementation of the role-change verb. The colonel `SetUserRole`
      # Logic class and the CLI `customers role promote/demote` command are thin
      # adapters over it. This is a MUTATING admin op, so it records exactly one
      # AdminAuditEvent per successful change (epic #20 CONTRACT 4 / #21). An
      # idempotent no-op change mutates nothing and is therefore not audited.
      #
      # `VALID_ROLES` is the single source of truth for assignable roles; the CLI
      # and colonel adapters both reference it rather than keeping their own copy.
      class SetRole
        include Onetime::LoggerMethods

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
          return Result.new(status: :no_change, customer: @customer, from: from, to: @role) if from == @role

          @customer.role = @role
          @customer.save

          # One audit event per successful mutation, emitted from the op layer.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: 'customer.set_role',
            target: @customer.extid,
            result: :success,
            detail: { from: from, to: @role },
          )

          # debug level (not info): the audit event is the durable record, and an
          # info-level line here would surface in CLI stderr and break the CLI's
          # bit-for-bit output contract.
          auth_logger.debug "[customer.set_role] #{@customer.extid} #{from} -> #{@role} by #{actor_label}"
          Result.new(status: :success, customer: @customer, from: from, to: @role)
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

# apps/web/auth/operations/customers/stop_impersonation.rb
#
# frozen_string_literal: true

require 'onetime/session/impersonation'

module Auth
  module Operations
    module Customers
      # STOP a colonel impersonation on the current session.
      #
      # A deliberately thin wrapper over
      # {Onetime::SessionImpersonation.stop!}. The audit event lives in the
      # primitive, NOT here, because two unrelated paths end an impersonation:
      # this operation (the operator pressed the button) and expiry inside
      # {Onetime::SessionImpersonation.active} (nobody pressed anything), plus
      # the four resolver-detected invalidations. If the event were emitted
      # here, every path but this one would end an impersonation silently — the
      # exact asymmetry that made the original design record starts without
      # stops.
      #
      # Idempotent: stopping a session that is not impersonating mutates
      # nothing, records nothing, and reports `:no_change`.
      class StopImpersonation
        include Onetime::LoggerMethods

        AUDIT_VERB = Onetime::SessionImpersonation::AUDIT_VERB_STOP

        # @!attribute status [r]
        #   @return [Symbol] :stopped, or :no_change when nothing was active
        # @!attribute target_extid [r]
        #   @return [String, nil] who the session had been presenting as —
        #     what the caller redirects back to in the admin console
        Result = Data.define(:status, :actor, :target_extid, :impersonation_id, :ended_by)

        # @param session [#[], #delete] the operator's live Rack session
        # @param actor [String, #extid, #email] the REAL operator's PUBLIC
        #   identity, for logging. The AUDIT actor is read from the session by
        #   the primitive, so an adapter cannot mis-attribute the trail by
        #   passing a different one here.
        # @param ended_by [String] one of the ENDED_BY_* constants; defaults to
        #   the operator-initiated path.
        def initialize(session:, actor:, ended_by: Onetime::SessionImpersonation::ENDED_BY_OPERATOR)
          @session  = session
          @actor    = normalize_actor(actor)
          @ended_by = ended_by.to_s
        end

        # @return [Result]
        def call
          marker = Onetime::SessionImpersonation.stop!(@session, ended_by: @ended_by)

          unless marker
            return Result.new(
              status: :no_change,
              actor: @actor,
              target_extid: nil,
              impersonation_id: nil,
              ended_by: @ended_by,
            )
          end

          auth_logger.info(
            "[customer.impersonate.stop] #{marker['target_extid']} by #{@actor} " \
            "id=#{marker['id']} ended_by=#{@ended_by}",
          )

          Result.new(
            status: :stopped,
            actor: @actor,
            target_extid: marker['target_extid'],
            impersonation_id: marker['id'],
            ended_by: @ended_by,
          )
        end

        private

        # PUBLIC identity string (extid/email), never an internal objid.
        def normalize_actor(actor)
          return actor if actor.is_a?(String)
          return actor.extid if actor.respond_to?(:extid) && !actor.extid.to_s.empty?
          return actor.email if actor.respond_to?(:email)

          nil
        end
      end
    end
  end
end

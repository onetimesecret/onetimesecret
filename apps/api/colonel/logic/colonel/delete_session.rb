# apps/api/colonel/logic/colonel/delete_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/delete_session'

module ColonelAPI
  module Logic
    module Colonel
      # Revoke (delete / terminate) a single session (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::Delete} — the single,
      # audited implementation of the session-delete verb (epic #40 / CONTRACT 4).
      # This class keeps only the HTTP concerns (param validation + the not-found
      # 404); the op owns the model mutation and the AdminAuditEvent.
      #
      # Deleting a session logs that user out mid-flight, so the UI gates this
      # behind AdminConfirmDialog typed-confirmation (retype the session id).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class DeleteSession < ColonelAPI::Logic::Base
        attr_reader :session_id, :result

        def process_params
          @session_id = sanitize_identifier(params['session_id'])
          raise_form_error('Session ID is required', field: :session_id) if session_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # 404 when there is no live session for this id, so the UI can tell
          # "already gone" from a real failure. The op is idempotent regardless.
          unless Onetime::Operations::Sessions::Store.find_key(Familia.dbclient, session_id)
            raise_not_found('Session not found')
          end
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Sessions::Delete.new(
            session_id: session_id,
            actor: cust.extid,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              session_id: result.session_id,
              deleted: result.status == :deleted,
            },
            details: {
              message: 'Session revoked successfully',
            },
          }
        end
      end
    end
  end
end

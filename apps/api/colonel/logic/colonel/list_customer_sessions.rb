# apps/api/colonel/logic/colonel/list_customer_sessions.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/list_for_customer'

module ColonelAPI
  module Logic
    module Colonel
      # List one customer's sessions from the metadata sidecar (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::ListForCustomer} — the
      # per-customer session view (spec docs/specs/colonel-ui/40-*). Unlike
      # {ListSessions} (the GLOBAL console, which SCANs + decrypts the keyspace),
      # this reads Customer#active_sessions and resolves each sid to a lightweight
      # {Onetime::SessionMetadata} record — no scan, no decrypt, no blob read.
      #
      # Read-only: no AdminAuditEvent (CONTRACT 4 — audit is for mutations). The
      # op self-heals its index (prunes stale sids), but that is not a session
      # mutation and is not audited.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      #
      # The safe_dump allow-list on SessionMetadata (adaptation #6) is the security
      # boundary: rows carry NO token, NO decrypted payload, NO email/secret
      # material — the frontend physically cannot render one.
      class ListCustomerSessions < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelCustomerSessions' }.freeze

        attr_reader :user_id, :result

        def process_params
          @user_id = sanitize_identifier(params['user_id'])
          raise_form_error('User ID is required', field: :user_id) if user_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          @result = Onetime::Operations::Sessions::ListForCustomer.new(
            custid: user_id,
          ).call

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              sessions: result.sessions,
              count: result.count,
            },
          }
        end
      end
    end
  end
end

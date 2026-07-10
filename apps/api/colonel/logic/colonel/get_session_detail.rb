# apps/api/colonel/logic/colonel/get_session_detail.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/sessions/inspect_session'

module ColonelAPI
  module Logic
    module Colonel
      # Inspect a single session (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::Inspect} — the single
      # implementation of the session-inspect verb (epic #40). Resolves the session
      # in raise_concerns (404 when absent) and surfaces a typed field read-out plus
      # the full parsed payload for the detail drawer's raw inspector.
      #
      # Read-only: no AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetSessionDetail < ColonelAPI::Logic::Base
        attr_reader :session_id, :result

        def process_params
          @session_id = sanitize_identifier(params['session_id'])
          raise_form_error('Session ID is required', field: :session_id) if session_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @result = Onetime::Operations::Sessions::Inspect.new(session_id: session_id).call
          raise_not_found('Session not found') unless result.found
        end

        def process
          success_data
        end

        def success_data
          data = result.data || {}
          {
            record: {
              session_id: result.session_id,
              key: result.key,
              ttl: result.ttl,
              authenticated: data['authenticated'] ? true : false,
              email: data['email'],
              external_id: data['external_id'] || data['account_external_id'],
              account_id: data['account_id'],
              role: data['role'],
              locale: data['locale'],
              ip_address: data['ip_address'],
              # User agent + the org the session is acting in — the "add more
              # information" fields the identity blob already carries but the
              # read-out didn't surface. org_context keys are namespaced
              # (`org_context:<uuid>`); extract_org_context recovers the id.
              user_agent: data['user_agent'],
              org_context: extract_org_context(data),
              authenticated_at: data['authenticated_at'],
              authenticated_by: data['authenticated_by'],
              active_session_id: data['active_session_id'],
            },
            details: {
              # Full parsed session payload for the raw inspector (colonel-only;
              # parity with `bin/ots session inspect`, which prints every key).
              data: data,
            },
          }
        end

        # The active org id from the namespaced `org_context:<uuid>` key the
        # session carries (nil for anonymous / single-org sessions).
        def extract_org_context(data)
          key = data.keys.find { |k| k.to_s.start_with?('org_context:') }
          key&.to_s&.delete_prefix('org_context:')
        end
      end
    end
  end
end

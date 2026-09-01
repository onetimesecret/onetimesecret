# apps/api/colonel/logic/colonel/list_customer_sessions.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

require_relative '../base'
require 'onetime/models/session_metadata'
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
      # ## Audited as an OBSERVATION (#4335)
      #
      # Mutates nothing, so it writes nothing to the OPERATOR trail. It is on
      # the curated list because it answers a question about ONE NAMED PERSON —
      # where and when they are currently signed in. The safe_dump allowlist
      # keeps the ROWS clean (no token, no payload, no email), which is a
      # different guarantee from "nobody needs to know who asked". The op also
      # self-heals its index (prunes stale sids); that is not a session mutation
      # and is still not audited as one.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      #
      # The safe_dump allow-list on SessionMetadata (adaptation #6) is the security
      # boundary: rows carry NO token, NO decrypted payload, NO email/secret
      # material — the frontend physically cannot render one.
      class ListCustomerSessions < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'colonelCustomerSessions' }.freeze

        AUDIT_VERB = 'session.list_for_customer'

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

          record_access_event

          success_data
        end

        # The target is the customer whose sessions were listed — the subject of
        # the observation. Detail is a count, never the rows: session handles
        # are non-bearer but they are still per-session identifiers, and the
        # trail does not need them to answer "who looked at whose sessions".
        # `user_id` is already length-bounded by sanitize_identifier.
        def record_access_event
          Onetime::ColonelAuditEvent.record_access(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: user_id,
            result: :success,
            detail: { sessions: result.count },
          )
        end

        def success_data
          {
            record: {},
            # safe_dump is the HTTP boundary (ADR-040): serialize it, never the
            # Result's #to_h (which exposes internal Entry objects + join keys).
            # Rows now identify a session by its non-bearer session_handle (F-01),
            # so the acting colonel's own row is matched by handle, not raw sid.
            details: result.safe_dump.merge(
              current_session_handle: current_session_handle,
            ),
          }
        end

        private

        # The acting colonel's OWN request session, as the non-bearer HANDLE the
        # sidecar rows expose (SessionMetadata#session_handle), so the UI can badge
        # the colonel's own row and disable its (no-op) self-revoke WITHOUT the
        # response ever carrying a replayable cookie value — not even the acting
        # colonel's own. nil when the session can't be identified.
        def current_session_handle
          sid = current_session_id
          return nil if sid.nil?

          Onetime::SessionMetadata.handle_for(sid)
        end

        # The colonel's own plain sid (safe_session_id yields a Rack SessionId
        # object; #public_id is the cookie value == SessionMetadata#session_id).
        # INTERNAL only — never serialized; it is digested into the handle above.
        # nil when the session can't be identified (e.g. Hash session in JSON auth).
        def current_session_id
          sid = safe_session_id
          return nil if sid.nil?

          sid.respond_to?(:public_id) ? sid.public_id : sid.to_s
        end
      end
    end
  end
end

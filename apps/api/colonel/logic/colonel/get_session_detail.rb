# apps/api/colonel/logic/colonel/get_session_detail.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require 'onetime/operations/sessions/store'
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
      # ## Non-bearer identifier (#4330)
      #
      # The route takes a {Onetime::SessionMetadata.handle_for} handle, not the raw
      # session id: that id is byte-identical to the `onetime.session` cookie, so
      # rendering it in the console handed every screen share and log capture a
      # replayable credential. The handle is resolved back to a sid server-side by
      # {Onetime::Operations::Sessions::Store.resolve_handle} and the sid never
      # crosses the HTTP boundary — not in `record`, not in `details.data`.
      #
      # Read-only: no ColonelAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class GetSessionDetail < ColonelAPI::Logic::Base
        include AccountIdentifier

        # Session payload keys the raw inspector must never render: the drawer
        # prints `details.data` verbatim through JsonViewer and `csrf` is a live
        # token. Redaction is server-side so no client can regress it.
        REDACTED_PAYLOAD_KEYS = %w[csrf].freeze

        attr_reader :session_handle, :result, :scan_capped

        def process_params
          @session_handle = sanitize_identifier(params['session_handle']).to_s.downcase
          # Optional owner hint (see Store.resolve_handle). NOT authorization — it
          # only picks a cheaper search space; a wrong hint falls through to the
          # bounded scan. sanitize_account_identifier, not sanitize_identifier:
          # the latter strips `@` and `.` out of an email hint.
          @owner_hint     = sanitize_account_identifier(params['user_id'])
          raise_form_error('Session handle is required', field: :session_handle) if session_handle.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
          # The one exception to "colonel reads are never rate-limited" (#4329):
          # this is the one colonel read whose cost is not O(1) — a bounded scan
          # plus up to MAX_SCAN HMACs when the owner hint misses. Charged before
          # the resolution it bounds, and before the 404, so a scanner cannot
          # walk the handle space for free.
          enforce_colonel_handle_resolve_limit!(cust&.extid)

          # A malformed handle resolves to nothing and 404s like an unknown one,
          # so a scanner cannot tell "bad shape" from "no such session".
          @session_id, @scan_capped = Onetime::Operations::Sessions::Store.resolve_handle(
            Familia.dbclient, session_handle, owner_hint: @owner_hint
          )
          raise_not_found('Session not found') unless @session_id

          @result = Onetime::Operations::Sessions::Inspect.new(session_id: @session_id).call
          raise_not_found('Session not found') unless result.found
        end

        def process
          success_data
        end

        def success_data
          data = redacted_payload(result.data || {})
          {
            record: {
              # The non-bearer handle the caller sent — NEVER the raw sid, and
              # never `result.key` (which is literally "session:<sid>").
              session_handle: session_handle,
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
              # parity with `bin/ots session inspect`, which prints every key),
              # minus the credential keys.
              data: data,
              # True when the bounded scan hit its cap during resolution: a 404
              # from this endpoint then means "not among the keys sampled", not
              # "does not exist". The console says so rather than lying.
              scan_capped: scan_capped,
            },
          }
        end

        private

        # Strip live credential material from the payload the drawer renders
        # verbatim. Note `elevated_until` (#4327) is deliberately NOT redacted —
        # it is elevation state, not a credential.
        def redacted_payload(data)
          data.reject { |key, _| REDACTED_PAYLOAD_KEYS.include?(key.to_s) }
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

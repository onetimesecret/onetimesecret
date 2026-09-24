# apps/api/colonel/logic/colonel/delete_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'account_identifier'
require_relative 'current_session'
require 'onetime/operations/sessions/store'
require 'onetime/operations/sessions/delete_session'
require 'onetime/operations/sessions/inspect_session'

module ColonelAPI
  module Logic
    module Colonel
      # Revoke (delete / terminate) a single session (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::Delete} — the single,
      # audited implementation of the session-delete verb (epic #40 / CONTRACT 4).
      # This class keeps only the HTTP concerns (param validation + the not-found
      # 404); the op owns the model mutation and the ColonelAuditEvent.
      #
      # Deleting a session logs that user out mid-flight, so the UI gates it behind
      # AdminConfirmDialog typed-confirmation (retype the session owner's email).
      #
      # ## Non-bearer identifier (#4330)
      #
      # The route takes a {Onetime::SessionMetadata.handle_for} handle — the same
      # shape the per-customer {RevokeCustomerSession} already accepted — never the
      # raw sid, which IS the `onetime.session` cookie. The handle is resolved back
      # server-side; the op receives the sid, the response echoes the handle.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class DeleteSession < ColonelAPI::Logic::Base
        include AccountIdentifier
        include CurrentSession

        attr_reader :session_handle, :session_id, :reason, :result

        def process_params
          @session_handle = sanitize_identifier(params['session_handle']).to_s.downcase
          # Optional owner hint (see Store.resolve_handle). NOT authorization — it
          # only picks a cheaper search space; a wrong hint falls through to the
          # bounded scan. sanitize_account_identifier, not sanitize_identifier:
          # the latter strips `@` and `.` out of an email hint.
          @owner_hint     = sanitize_account_identifier(params['user_id'])
          # OPTIONAL operator-supplied why (#4338) — query string, since this is
          # a DELETE. See ColonelAPI::Logic::Base#operator_reason_param.
          @reason         = operator_reason_param
          raise_form_error('Session handle is required', field: :session_handle) if session_handle.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
          # Handle resolution is the one colonel path whose cost is not O(1) — a
          # bounded scan plus up to MAX_SCAN HMACs when the owner hint misses —
          # so it carries its own bucket (#4329), charged before the resolution
          # it bounds. This is NOT the destructive budget: that one is charged as
          # the last line of this method, only for requests about to execute.
          enforce_colonel_handle_resolve_limit!(cust&.extid)

          # 404 when the handle names no live session (unknown, stale, or
          # malformed — indistinguishable on purpose), so the UI can tell
          # "already gone" from a real failure. The op is idempotent regardless.
          # resolve_handle answers [sid, scan_capped]; the truncation flag is
          # surfaced by the detail READ, not by a mutation ack, so only the sid
          # is kept here.
          @session_id, = Onetime::Operations::Sessions::Store.resolve_handle(
            Familia.dbclient, session_handle, owner_hint: @owner_hint
          )
          raise_not_found('Session not found') unless session_id

          # TIER 1 (#4326). The URL carries only the opaque handle, so the
          # confirmation is the session OWNER — an identifier the operator reads
          # off the row and the handle cannot be transformed into.
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: owner_token,
            confirm_subject: owner_subject,
            field: :session_handle,
          )

          # INTERLOCK — step 4, after proof (#4328). Revoking the session you
          # are working in signs YOU out mid-incident; sign-out is the verb for
          # that. Placed after the guard so the 422 cannot be used as a free
          # "is this handle mine?" oracle over the whole session list by a
          # caller holding nothing but the cookie. Compares HANDLES, so the raw
          # bearer sid never enters the comparison path.
          if current_session_handle && current_session_handle == session_handle
            raise_form_error(
              'Cannot revoke your own active session. Use sign-out instead.',
              field: :session_handle,
            )
          end

          charge_destructive_budget!
        end

        def process
          # Delegate the model mutation + audit to the single op implementation.
          # actor is the acting colonel's PUBLIC id (never an objid).
          @result = Onetime::Operations::Sessions::Delete.new(
            session_id: session_id,
            actor: cust.extid,
            reason: reason,
          ).call

          success_data
        end

        def success_data
          {
            record: {
              # Echo the non-bearer handle the caller sent — NEVER the raw sid.
              session_handle: session_handle,
              deleted: result.status == :deleted,
            },
            details: {
              message: 'Session revoked successfully',
            },
          }
        end

        private

        # The confirmation token: the session owner's email, its external id when
        # the payload carries no address, and the handle itself for an anonymous
        # (identity-less) session — which has no owner to name. Never blank, so
        # the guard's blank-expected tripwire stays a programming-error signal.
        # Mirrors the console row, which computes the same three-way fallback.
        def owner_token
          @owner_token ||= begin
            data = inspected_payload
            [data['email'], data['external_id'], data['account_external_id']]
              .map { |value| value.to_s.strip }
              .find { |value| !value.empty? } || session_handle
          end
        end

        # Names what to retype, honestly: an anonymous session's token is the
        # handle, and telling the operator to send an email address they cannot
        # find would be an unanswerable 403.
        def owner_subject
          if owner_token == session_handle
            'the session handle (this session carries no owner identity)'
          else
            "the session owner's email address"
          end
        end

        # Read-only, and the ONLY reason this mutation loads the payload: the
        # confirmation token has to name the owner. Reads never audit.
        def inspected_payload
          Onetime::Operations::Sessions::Inspect.new(session_id: session_id).call.data || {}
        end
      end
    end
  end
end

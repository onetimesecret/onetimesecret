# apps/api/colonel/logic/colonel/list_sessions.rb
#
# frozen_string_literal: true

require_relative '../base'
require_relative 'current_session'
require 'onetime/operations/sessions/list_sessions'

module ColonelAPI
  module Logic
    module Colonel
      # List active sessions (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Sessions::List} — the single
      # implementation of the session-list verb (epic #40). This class keeps only
      # the HTTP concerns (param coercion + role gate); the op owns the bounded
      # scan, the optional search filter, and pagination.
      #
      # Rows identify a session by `session_handle` only: this adapter does NOT
      # pass `reveal_session_id`, so the op strips the raw sid and its Redis key
      # before they can reach the wire (#4330). The search term matches identity
      # fields or a handle prefix, so the console's search box still works over
      # what it now displays.
      #
      # Read-only: no ColonelAuditEvent (CONTRACT 4 — audit is for mutations).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListSessions < ColonelAPI::Logic::Base
        # Same mixin the per-customer panel uses, so the global console can badge
        # and disable the acting colonel's own row against the SAME definition
        # the DeleteSession interlock refuses on (#4328).
        include CurrentSession

        SCHEMAS = { response: 'colonelSessions' }.freeze

        attr_reader :sessions, :pagination_meta

        def process_params
          @page     = (params['page'] || 1).to_i
          @per_page = (params['per_page'] || 50).to_i
          @search   = sanitize_plain_text(params['search'], max_length: 255) if params['search']
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          result = Onetime::Operations::Sessions::List.new(
            page: @page,
            per_page: @per_page,
            search: @search,
          ).call

          @sessions        = result.sessions
          @pagination_meta = {
            page: result.page,
            per_page: result.per_page,
            total_count: result.total_count,
            total_pages: result.total_pages,
          }
          # Keyspace shape for the console: `total_count` counts only the
          # identity sessions shown (CSRF-only anonymous ones are excluded), so
          # surface how many were scanned/hidden and whether the bounded scan
          # was truncated — otherwise a short list would read as "few sessions"
          # when the truth is "few authenticated sessions among many."
          @scan_meta       = {
            scanned: result.scanned,
            anonymous_count: result.anonymous_count,
            scan_capped: result.scan_capped,
          }

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              sessions: sessions,
              pagination: pagination_meta,
              scan: @scan_meta,
              # The acting colonel's own row, as a HANDLE (never the sid). The
              # console disables its revoke button; the server refuses it too
              # (DeleteSession, #4328) — this only spares the operator the 422.
              # nil when the session can't be identified.
              current_session_handle: current_session_handle,
            },
          }
        end
      end
    end
  end
end

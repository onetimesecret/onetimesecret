# apps/api/colonel/logic/colonel/list_sessions.rb
#
# frozen_string_literal: true

require_relative '../base'
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
      # Read-only: no AdminAuditEvent (CONTRACT 4 — audit is for mutations).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ListSessions < ColonelAPI::Logic::Base
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

          success_data
        end

        def success_data
          {
            record: {},
            details: {
              sessions: sessions,
              pagination: pagination_meta,
            },
          }
        end
      end
    end
  end
end

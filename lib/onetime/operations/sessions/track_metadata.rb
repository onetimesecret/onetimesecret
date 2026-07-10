# lib/onetime/operations/sessions/track_metadata.rb
#
# frozen_string_literal: true

require 'onetime/models/session_metadata'

module Onetime
  module Operations
    module Sessions
      # Upsert the per-session sidecar (Onetime::SessionMetadata) and index the
      # sid into the owning customer's active_sessions set — the write half of the
      # per-customer session view (spec docs/specs/colonel-ui/40-*).
      #
      # Called from Onetime::Session#write_session (adaptation #2): that is the
      # ONLY place the plain sid is guaranteed present alongside the post-login
      # session_data hash, and it commits ~per request so last_activity_at
      # naturally refreshes. It is NOT populated from Auth::Operations::SyncSession
      # — the sid is not reliably available there (its idempotency code proves this
      # with `@session.id rescue SecureRandom.hex`).
      #
      # BEST-EFFORT BY CONTRACT: this is a convenience index, never authoritative
      # (the encrypted session blob is). #call NEVER raises — any failure is logged
      # and swallowed (the SyncSession#stamp_last_login precedent). Losing metadata
      # must never break a request or a login.
      class TrackMetadata
        # @param session_id [String] the PLAIN session id (== live blob key name).
        # @param session_data [Hash] the post-login session hash (string keys) as
        #   seen by write_session. Anonymous/CSRF-only sessions lack
        #   'authenticated'/'external_id' and are a no-op.
        # @param dbclient [Object, nil] reserved for symmetry with sibling ops;
        #   the Familia models resolve their own connection.
        def initialize(session_id:, session_data:, dbclient: nil)
          @session_id   = session_id
          @session_data = session_data || {}
          @dbclient     = dbclient
        end

        # @return [Onetime::SessionMetadata, nil] the upserted record, or nil on
        #   no-op / swallowed failure.
        def call
          extid = @session_data['external_id']

          # Only index authenticated sessions with a resolvable customer. IP/UA
          # masking is NOT done here — Otto masks them upstream before they land
          # in session_data (adaptation #3), so both are copied AS-IS.
          return nil unless @session_data['authenticated'] && extid && !@session_id.to_s.empty?

          customer = Onetime::Customer.find_by_extid(extid)
          return nil if customer.nil?

          now = Familia.now.to_i

          meta = Onetime::SessionMetadata.load(@session_id) ||
                 Onetime::SessionMetadata.new(session_id: @session_id)

          # created_at is set once and preserved on refresh (||= backfills a
          # legacy nil too). last_activity_at always advances. No HSETNX: declared
          # fields persist as "null" so HSETNX would never fire — a load/save
          # upsert is the correct best-effort tool here.
          meta.created_at     ||= now
          meta.last_activity_at = now
          meta.ip_address       = @session_data['ip_address']
          meta.user_agent       = @session_data['user_agent']
          meta.user_id          = extid
          meta.org_id           = org_id
          meta.auth_method      = auth_method
          meta.mfa_used         = mfa_used
          meta.save

          # Score by last-activity so the per-customer list reads newest-first.
          customer.active_sessions.add(@session_id, now)

          meta
        rescue StandardError => ex
          OT.le(
            '[Sessions::TrackMetadata] sidecar upsert failed (swallowed)',
            exception: ex,
            session_id: @session_id,
          )
          nil
        end

        private

        # DEVIATION from brief adaptation (org_id): store nil, not the namespaced
        # `org_context:<...>` suffix. The brief said "from session_data org_context
        # if present"; that assumption is wrong for this codebase. The only org-ish
        # key the session carries is `org_context:<customer.objid>` (see
        # apps/web/auth/config/hooks/login.rb) — its suffix is the CUSTOMER objid,
        # NOT an org id. Storing it in a field literally named org_id would be a
        # data-integrity bug that misleads every downstream consumer. There is no
        # reliable org id in write_session's session_data, so nil is the honest
        # value. A real value would require reading what OrganizationLoader caches
        # under that key — out of scope for this MVP field.
        def org_id
          nil
        end

        # 'omniauth' when a positive omniauth marker survives into the session,
        # else nil. We do NOT default to 'password': by the time write_session
        # runs, the after-login hooks have deleted the omniauth markers (see
        # omniauth.rb / login.rb), so a blanket 'password' would mislabel SSO
        # sessions. nil = "not reliably known" (adaptation: "if uncertain, nil").
        def auth_method
          return 'omniauth' if @session_data.keys.any? { |k| k.to_s.start_with?('omniauth') }

          nil
        end

        # nil unless clearly derivable. write_session's session_data carries no
        # stable MFA marker (awaiting_mfa is deleted on successful auth), so we do
        # not invent one — the field exists for a future enrichment path.
        def mfa_used
          nil
        end
      end
    end
  end
end

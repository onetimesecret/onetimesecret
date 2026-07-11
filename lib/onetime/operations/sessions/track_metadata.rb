# lib/onetime/operations/sessions/track_metadata.rb
#
# frozen_string_literal: true

require 'onetime/models/session_metadata'
require 'onetime/application/organization_loader'

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
        # OrganizationLoader is the single authoritative accessor for a session's
        # active organization (explicit-selection → domain → default → first-org,
        # with a per-request session cache). We call it rather than reading the
        # cache directly so org_id is populated even on the login-time write,
        # before any auth strategy has warmed the cache.
        include Onetime::Application::OrganizationLoader

        # @param session_id [String] the PLAIN session id (== live blob key name).
        # @param session_data [Hash] the post-login session hash (string keys) as
        #   seen by write_session. Anonymous/CSRF-only sessions lack
        #   'authenticated'/'external_id' and are a no-op.
        # @param env [Hash, nil] the Rack env, forwarded to OrganizationLoader for
        #   domain/header-based org selection. nil in tests falls back to the
        #   customer's default/first org (env-dependent steps are skipped).
        # @param dbclient [Object, nil] reserved for symmetry with sibling ops;
        #   the Familia models resolve their own connection.
        def initialize(session_id:, session_data:, env: nil, dbclient: nil)
          @session_id   = session_id
          @session_data = session_data || {}
          @env          = env
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
          meta.org_id           = active_org_id(customer)
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

        # org_id = the objid of the session's ACTIVE ORGANIZATION.
        #
        # WHAT `org_id` IS: the organization currently active for this session, as
        #   resolved by Onetime::Application::OrganizationLoader. It is mutable —
        #   the user can switch orgs mid-session — so it is resolved on every write,
        #   not stamped once at auth time.
        #
        # WHERE IT COMES FROM (do not confuse the key with its value):
        #   OrganizationLoader caches the active org in the session under the key
        #   STRING `org_context:<customer.objid>`. The key's SUFFIX is the CUSTOMER
        #   objid — it namespaces the cache entry per customer and is NOT an org id.
        #   The key's VALUE is a hash `{ organization_id: <org.objid>, expires_at: }`
        #   whose `organization_id` IS the real active-org objid. An earlier version
        #   of this method read the key's suffix and concluded "no org source
        #   exists" — that was a misread; the org objid lives in the value.
        #
        # We call load_organization_context (the canonical resolver) rather than
        # reading that cache directly: the resolver read-throughs the cache and,
        # on a miss (e.g. the login-time write, before any auth strategy has run),
        # resolves and returns the org. That is what guarantees every authenticated
        # session's metadata carries the active org, with no fallback branch here.
        #
        # Wrapped in its own rescue: an org-resolution hiccup must degrade org_id to
        # nil, never abort the whole sidecar row (ip/ua/user still get written).
        def active_org_id(customer)
          load_organization_context(customer, @session_data, @env)[:organization_id]
        rescue StandardError => ex
          OT.ld "[Sessions::TrackMetadata] org resolution failed: #{ex.message}"
          nil
        end

        # auth_method is the PRIMARY login method, STAMPED ONCE at authentication
        # time into the session (`session['auth_method']` in
        # apps/web/auth/config/hooks/login.rb, from Rodauth's authenticated_by.first)
        # and copied verbatim here. Values: 'password', 'email_auth' (magic link),
        # 'webauthn', 'omniauth'. It is NOT re-derived per write — by the time
        # write_session runs the mechanism leaves no trace in session_data (omniauth
        # markers are deleted; password/magic-link/webauthn never wrote one). nil
        # only for legacy sessions minted before the auth-time stamp existed.
        def auth_method
          @session_data['auth_method']
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

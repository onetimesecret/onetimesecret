# lib/onetime/operations/sessions/track_metadata.rb
#
# frozen_string_literal: true

require_relative '../../models/session_metadata'
require_relative '../../application/organization_loader'
require_relative '../../application/auth_strategies/admin_session_lifetime'

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

        # Otto's GeoResolver sentinel for "no country resolved" — normalized to
        # nil, never stored. Onetime::SessionMetadata#geo_country (the single
        # read-side chokepoint) maps '**' to nil anyway, so persisting it would
        # only waste a hash field that every reader ignores.
        UNKNOWN_COUNTRY = '**'

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

          # A REFUSED request is not activity (#4331). The admin-surface session
          # bounds read last_activity_at from this very record, so stamping it
          # here for a request the auth strategy just rejected would slide the
          # idle window forward and let the next request through — the bound
          # would only ever cost an attacker one 401. The strategy sets the flag;
          # this is the only reader. Note it suppresses the whole upsert, the
          # active_sessions score included, for exactly that one request.
          return nil if admin_session_expired?

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
          meta.geo_country      = geo_country

          # Internal join key, copied VERBATIM like auth_method: the digest is
          # computed at auth time by the Rodauth side (compute_hmac needs the
          # Rodauth instance, which this operation does not have) and stamped into
          # the session there. Set unconditionally — Rodauth re-mints its token on
          # every update_session, so a stale digest must be overwritten, and a
          # session predating the stamp simply writes nil.
          meta.active_session_id_hmac = @session_data['active_session_id_hmac']

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

        # True when this request was refused by the #4331 admin-surface session
        # bounds. See the call site in #call for why it suppresses the upsert.
        def admin_session_expired?
          return false unless @env.respond_to?(:[])

          !@env[Onetime::Application::AuthStrategies::AdminSessionLifetime::EXPIRED_ENV_KEY].nil?
        rescue StandardError
          false
        end

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

        # geo_country is the country Otto's IPPrivacyMiddleware already resolved
        # for this request and stamped into the Rack env (otto.privacy.geo_country,
        # ISO 3166-1 alpha-2 or the '**' unknown sentinel). It runs upstream of the
        # session write, so this is a plain env read — NOT an IP lookup, and never
        # derived from the (masked) ip_address. nil when @env is absent (e.g. tests
        # that call TrackMetadata directly with env: nil) or the privacy layer is
        # disabled; consumers render nil/absent as "Unknown".
        #
        # Normalized to the canonical alpha-2 form (strip/upcase) so a custom geo
        # header emitting a lowercase or padded value stores consistently across
        # every surface, matching Onetime::Security::RequestContext#normalize_country.
        # The '**' sentinel, like blank or malformed values, stores nil — the
        # sentinel never persists and never reaches a client (the
        # {Onetime::SessionMetadata#geo_country} reader enforces the same on the
        # way out, including for legacy records that stored it verbatim).
        def geo_country
          raw = @env&.dig('otto.privacy.geo_country')
          return nil if raw.nil?

          normalized = raw.to_s.strip
          return nil if normalized.empty? || normalized == UNKNOWN_COUNTRY

          upcased = normalized.upcase
          upcased.match?(/\A[A-Z]{2}\z/) ? upcased : nil
        end
      end
    end
  end
end

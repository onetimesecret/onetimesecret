# lib/onetime/application/auth_strategies/admin_session_lifetime.rb
#
# frozen_string_literal: true

module Onetime
  module Application
    module AuthStrategies
      # Shorter idle + absolute session bounds for the ADMIN API SURFACE only
      # (#4331).
      #
      # SCOPE IS THE SURFACE, NOT THE SESSION. One onetime.session cookie serves
      # the colonel API, the tenant app and the Rodauth app (Onetime::Session is
      # mounted once, in the universal middleware stack), so expiring the session
      # object would log a colonel out of the customer app too — and on a
      # self-hosted install the colonel often IS the only customer. Bounding the
      # surface gives the security property (a stale admin session cannot act)
      # with no tenant-side regression. Splitting the admin surface onto its own
      # cookie remains the fuller fix.
      #
      # /api/colonel ONLY. The /colonel SPA shell is deliberately NOT bounded: a
      # bare 401 on an HTML navigation has no defined UX, and the expired-session
      # banner lives inside the SPA. The shell loads, its first API call 401s, the
      # banner renders. The shell alone can do nothing. This is why the prefix
      # below is NOT AdminNetworkIsolation::SURFACES (%w[/colonel /api/colonel]) —
      # the two definitions are intentionally different, so do not "fix" the
      # divergence by sharing the constant.
      #
      # ABSOLUTE bound reads session['authenticated_at'], which both auth modes
      # stamp at login and which UpdatePassword re-stamps after a password change.
      # Nothing an attacker holding the cookie can do advances it, so this is the
      # bound that actually binds.
      #
      # IDLE bound reads SessionMetadata#last_activity_at, refreshed on every
      # authenticated write by Onetime::Operations::Sessions::TrackMetadata.
      # SessionMetadata is BEST-EFFORT and never authoritative: a session
      # predating the sidecar, one whose 30-day TTL lapsed, or one whose write was
      # swallowed has none. A missing sidecar therefore SKIPS the idle check
      # rather than failing it — hard-failing would log out live sessions for a
      # reason unrelated to their age.
      #
      # Two properties the idle bound depends on, both load-bearing:
      #
      #   1. The admin console makes NO periodic requests. TrackMetadata advances
      #      last_activity_at on every authenticated commit, so any poll would
      #      refresh it forever. See src/apps/admin/composables/useColonelElevation.ts
      #      — do not add a timer anywhere under src/apps/admin/.
      #   2. A REJECTED request is not activity. The caller stamps
      #      EXPIRED_ENV_KEY into the Rack env on refusal and TrackMetadata skips
      #      its upsert when it sees it; without that, the very request this
      #      module just refused would advance last_activity_at on its way out and
      #      the next one would sail through, making the bound a one-request speed
      #      bump.
      #
      # Residual, stated rather than hidden: last_activity_at is a SITE-WIDE
      # activity clock, so a colonel (or anyone holding their cookie) who touches
      # a tenant route keeps the admin idle window open. The absolute bound is
      # unaffected. Per-surface activity needs the separate admin session this
      # design deliberately defers.
      #
      # ## The one exempt request: password re-authentication
      #
      # REAUTH_EXEMPT names exactly one method and path,
      # `POST /api/colonel/reauthenticate`
      # (ColonelAPI::Logic::Colonel::ReauthenticateSession). It is how an
      # operator whose window lapsed gets it back by re-entering their
      # password instead of signing out and in. A bound that refused it would
      # leave sign-out as the only recovery, so neither bound refuses it.
      #
      # This does not weaken the bound for any other request:
      #
      #   - Only the bound is skipped. The request still passes every other
      #     session check in base_session_auth_strategy.rb and the shared
      #     evaluator: authenticated, identity, surface, suspension, the
      #     credential watermark (stale_credentials) and the active-session
      #     row; and the router still requires role=colonel.
      #   - The handler does nothing without the account password (the same
      #     dual-mode check as step-up), throttled by the colonel elevation
      #     limiter bucket.
      #   - A wrong password changes nothing: authenticated_at is not
      #     re-stamped, and the request is still NOT activity. When a bound
      #     had tripped, #admin_session_expiry_reason stamps EXPIRED_ENV_KEY
      #     for this request too, so TrackMetadata leaves last_activity_at
      #     where it was. Without that, any POST here, right password or not,
      #     would slide the idle window forward and reopen the whole surface.
      #   - A right password re-stamps authenticated_at (the absolute bound)
      #     and renews the session id, which ends the old id's SessionMetadata
      #     record. The handler then writes the new id's record through
      #     TrackMetadata itself (the idle bound), because the commit skips
      #     it for the reason above.
      #
      # Method and path are matched exactly (a trailing slash aside, as
      # #admin_api_request? normalizes it): `GET /api/colonel/reauthenticate`
      # and `POST /api/colonel/reauthenticate-x` are bounded like any other
      # admin request.
      module AdminSessionLifetime
        DEFAULT_IDLE_TIMEOUT     = 3_600    # 1 hour
        DEFAULT_ABSOLUTE_TIMEOUT = 43_200   # 12 hours

        ADMIN_API_PREFIX = '/api/colonel'

        # [method, full path] pairs neither bound refuses. One entry, on
        # purpose; see "The one exempt request" above before adding another.
        REAUTH_EXEMPT = [['POST', "#{ADMIN_API_PREFIX}/reauthenticate"].freeze].freeze

        # Rack env flag marking a request that arrived on an expired admin
        # session: set by the auth strategy when it refuses an admin request on
        # either bound, and by #admin_session_expiry_reason when it admits the
        # REAUTH_EXEMPT request past a tripped bound. Either way the request is
        # not activity. Read by Onetime::SessionActivity.refused?
        # (TrackMetadata and the session blob TTL).
        EXPIRED_ENV_KEY = 'onetime.admin_session_expired'

        # @param session [Hash, Rack::Session::Abstract::SessionHash] the raw session
        # @param cust [Onetime::Customer] the customer this request loaded
        # @param env [Hash] the Rack environment
        # @return [Symbol, nil] :absolute, :idle, or nil when the session may proceed
        def admin_session_expiry_reason(session, cust, env)
          reason = admin_session_bound_reason(session, cust, env)
          return reason unless reason && admin_reauth_exempt?(env)

          # Admitted, but not activity (see "The one exempt request").
          env[EXPIRED_ENV_KEY] = reason.to_s
          nil
        end

        private

        # Which bound, if any, this request's session is past. Ignores
        # REAUTH_EXEMPT; #admin_session_expiry_reason applies it.
        #
        # @return [Symbol, nil] :absolute, :idle, or nil
        def admin_session_bound_reason(session, cust, env)
          return nil unless admin_api_request?(env)
          return nil unless cust.role.to_s == 'colonel'
          return nil unless admin_session_lifetime_enabled?

          now = Familia.now.to_i

          absolute = admin_absolute_timeout
          if absolute.positive?
            stamped = session['authenticated_at'].to_i
            return :absolute if stamped.positive? && (now - stamped) > absolute
          end

          idle = admin_idle_timeout
          return nil unless idle.positive?

          last = admin_last_activity_at(session)
          return nil if last.nil? # best-effort sidecar missing -> skip, never fail
          return :idle if (now - last) > idle

          nil
        end

        def admin_api_request?(env)
          path = "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}"
          path == ADMIN_API_PREFIX || path.start_with?("#{ADMIN_API_PREFIX}/")
        rescue StandardError
          false
        end

        # Exact method, exact full path (SCRIPT_NAME + PATH_INFO, the same
        # mount-relative join #admin_api_request? uses), one trailing slash
        # tolerated. Anything unreadable is not exempt.
        def admin_reauth_exempt?(env)
          method = env['REQUEST_METHOD'].to_s.upcase
          path   = "#{env['SCRIPT_NAME']}#{env['PATH_INFO']}"
          path   = path.chomp('/') unless path == '/'

          REAUTH_EXEMPT.include?([method, path])
        rescue StandardError
          false
        end

        def admin_last_activity_at(session)
          sid = session.respond_to?(:id) ? session.id : nil
          sid = sid.respond_to?(:public_id) ? sid.public_id : sid&.to_s
          return nil if sid.to_s.empty?

          Onetime::SessionMetadata.load(sid)&.last_activity_at&.to_i
        rescue StandardError => ex
          OT.ld "[AdminSessionLifetime] sidecar read failed: #{ex.message}"
          nil
        end

        def admin_session_config
          OT.conf&.dig('site', 'admin', 'session') || {}
        end

        def admin_session_lifetime_enabled?
          admin_session_config.fetch('enabled', true) != false
        end

        # 0 legitimately DISABLES a bound, so this cannot use the positive_*
        # setting guard's "fall back to the default" behaviour: a configured 0
        # must stay 0. But it must NOT String#to_i an arbitrary value either —
        # `raw` arrives as whatever YAML parsed from `<%= ENV[...] || N %>`, so a
        # typo'd env is a String, and `"off".to_i` / `"none".to_i` is 0 (silently
        # disabling a security bound) while `"12h".to_i` is 12 (a 12-SECOND
        # lifetime). Accept only a clean non-negative integer — an Integer, or an
        # all-digits String; anything else (a non-numeric string, a YAML boolean
        # from `off`/`no`) falls back to the shipped default. Same intent as
        # colonel_rate_limiter.rb#positive_colonel_setting.
        def admin_timeout_setting(key, default)
          raw = admin_session_config[key]

          case raw
          when Integer then raw.negative? ? default : raw
          when String  then raw.match?(/\A\d+\z/) ? raw.to_i : default
          else default
          end
        end

        def admin_idle_timeout
          admin_timeout_setting('idle_timeout', DEFAULT_IDLE_TIMEOUT)
        end

        def admin_absolute_timeout
          admin_timeout_setting('absolute_timeout', DEFAULT_ABSOLUTE_TIMEOUT)
        end
      end
    end
  end
end

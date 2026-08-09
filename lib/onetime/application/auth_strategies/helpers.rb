# lib/onetime/application/auth_strategies/helpers.rb
#
# frozen_string_literal: true

require 'rack/request'
require 'otto'

#
# Shared helper methods for authentication strategies.
#
# Provides common functionality for loading users from sessions
# and building metadata hashes for auth results.
#
# @see Onetime::Application::AuthStrategies

module Onetime
  module Application
    module AuthStrategies
      # Shared helper methods for authentication strategies
      module Helpers
        # Build an authentication failure for explicitly-presented credentials
        # (an Authorization header) that were examined and rejected.
        #
        # The failure is TERMINAL — Otto's RouteAuthWrapper halts the strategy
        # chain and fails closed (401) regardless of strategy order, so a later
        # (or earlier) anonymous-capable strategy such as NoAuthStrategy cannot
        # let invalid credentials degrade to a silent anonymous 200 with a null
        # owner — EXCEPT when this same request already resolves a valid session
        # identity. In that case the failure is NON-terminal so the chain
        # continues to the session-resolving NoAuthStrategy: a valid session
        # OUTRANKS a rejected Authorization header, so a logged-in browser is
        # never 401'd mid-session by a stale cached Basic credential or by a
        # reverse proxy forwarding its own htpasswd header. That carve-out is
        # safe because the audit hole (item 1) was invalid credentials becoming
        # *anonymous*, and a session-authenticated request is not anonymous.
        #
        # This replaces the former env-marker guard
        # (`onetime.auth.credentialed_failure`) that NoAuthStrategy had to read:
        # the terminal/non-terminal decision now travels on the AuthFailure
        # itself, with no cross-strategy env coupling and no dependence on
        # credentialed strategies running BEFORE noauth in the chain. See
        # docs/security/audits/2026-07-29-api.md item 1 and
        # Otto::Security::Authentication::AuthFailure.
        #
        # Only use this for EXPLICITLY-presented credentials. Ambient
        # credentials (session cookies) must fail non-terminally via #failure
        # so an unauthenticated or stale session still degrades to anonymous
        # on noauth-capable routes rather than 401ing every browser request.
        #
        # @param reason [String] failure reason, e.g. '[CREDENTIALS_INVALID] ...'
        # @param env [Hash, nil] the Rack env, so the session carve-out can be
        #   evaluated. Passing nil (bare unit-level strategy calls) keeps the
        #   strict terminal behavior.
        # @return [Otto::Security::Authentication::AuthFailure]
        def credentialed_failure(reason, env = nil)
          return failure(reason) if valid_session_identity?(env)

          failure(reason, terminal: true)
        end

        # Loads customer from session if authenticated
        #
        # @param session [Hash] Rack session
        # @return [Onetime::Customer, nil] Customer if found, nil otherwise
        def load_user_from_session(session)
          return nil unless session
          return nil unless session['authenticated'] == true

          external_id = session['external_id']
          return nil if external_id.to_s.empty?

          cust = Onetime::Customer.find_by_extid(external_id)

          # Credential watermark (#3810): a session established before the
          # customer's last password change/reset must not resolve an identity.
          # This is the anonymous-capable path (NoAuthStrategy), so a stale
          # session degrades to nil/anonymous — never a 401 here; the
          # session-requiring strategies reject with SESSION_STALE_CREDENTIALS
          # in BaseSessionAuthStrategy instead.
          return nil if session_predates_credential_change?(session, cust)

          cust
        rescue StandardError => ex
          OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
          OT.ld ex.backtrace.first(3).join("\n")
          nil
        end

        # Whether a session blob was authenticated BEFORE the customer's last
        # credential change (#3810). This predicate — not the enumerative blob
        # deletion in the password hooks, which is hygiene — is the authoritative
        # session-revocation boundary: a blob the hooks never found still dies
        # here on its next request. Strict integer comparison of epoch seconds:
        #
        #   - No customer or no watermark (nil/0) => false. Deploying this check
        #     can never mass-logout customers who never changed a password.
        #   - Watermark set + missing authenticated_at (coerces to 0) => true.
        #     Fail-secure: an identity-bearing blob with no login timestamp
        #     cannot be proven to postdate the credential change.
        #   - authenticated_at == watermark => TRUE (rejected, treated as
        #     pre-change). The current session survives NOT via equality but
        #     because after_change_password re-stamps it to a value STRICTLY
        #     GREATER than the watermark, so it clears the `<=` boundary.
        #
        # @param session_data [Hash, #[], nil] Rack session (string keys)
        # @param cust [Onetime::Customer, nil] customer resolved from the session
        # @return [Boolean]
        def session_predates_credential_change?(session_data, cust)
          return false unless cust

          watermark = cust.last_password_update.to_i
          return false unless watermark.positive?

          authenticated_at = session_data ? session_data['authenticated_at'].to_i : 0
          authenticated_at <= watermark
        end

        # Builds standard metadata hash from env
        #
        # @param env [Hash] Rack environment
        # @param additional [Hash] Additional metadata to merge
        # @return [Hash] Metadata hash
        def build_metadata(env, additional = {})
          {
            ip: client_ip(env),
            user_agent: env['HTTP_USER_AGENT'],
            country: env['otto.privacy.geo_country'],
            domain_strategy: env['onetime.domain_strategy'],
            display_domain: env['onetime.display_domain'],
          }.merge(additional)
        end

        private

        # Whether THIS request already resolves a valid (non-stale) session
        # identity. Used only by #credentialed_failure to decide whether a
        # rejected Authorization header should fail the chain closed or defer to
        # the session. A nil/non-Hash env (bare unit-level strategy invocations)
        # or an anonymous/stale session yields false, preserving the strict
        # terminal default. Reuses #load_user_from_session so the credential
        # watermark staleness check (#3810) applies identically here — a session
        # that predates the customer's last credential change does NOT count as a
        # valid identity and cannot rescue a rejected Authorization header.
        #
        # @param env [Hash, nil] Rack environment
        # @return [Boolean]
        def valid_session_identity?(env)
          return false unless env.is_a?(Hash)

          !load_user_from_session(env['rack.session']).nil?
        end

        # Resolve the client IP for auth metadata.
        #
        # Prefers env['otto.client_ip'], the value resolved once by the universal
        # IPPrivacyMiddleware mount (trusted-proxy / depth resolution from
        # site.network.trusted_proxy, then privacy masking). Falls back to
        # Otto::Utils.resolve_client_ip when the middleware has not run (e.g. a
        # standalone auth strategy invocation in a unit test), so the trusted-proxy
        # contract holds even without the full stack. Bare Rack::Request#ip is the
        # last resort.
        #
        # @param env [Hash] Rack environment
        # @return [String, nil] resolved client IP
        def client_ip(env)
          canonical = env['otto.client_ip']
          return canonical if canonical && !canonical.empty?

          Otto::Utils.resolve_client_ip(env, env['otto.security_config'])
        rescue StandardError => ex
          # Unreachable in production (the middleware always sets
          # otto.client_ip); if it ever fires, the bare Rack fallback has no
          # trusted-proxy awareness and may return the ingress hop, so make the
          # failure visible rather than silently mis-attributing the IP.
          OT.le "[client_ip] resolve_client_ip failed, falling back to Rack::Request#ip: #{ex.message}"
          Rack::Request.new(env).ip
        end
      end
    end
  end
end

# lib/onetime/application/auth_strategies/helpers.rb
#
# frozen_string_literal: true

require 'rack/request'
require 'otto'

require_relative '../../session/customer_session_evaluator'

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

        # The shared customer-session verdict for this request. Compatibility
        # callers may project it to nil/boolean, but may never promote a refused
        # or unavailable verdict to an identity.
        def customer_session_verdict(session, env = nil)
          Onetime::CustomerSessionEvaluator.evaluate(session, env: env)
        end

        # Compatibility projection retained for credentialed strategies and
        # older callers. Identity is present only on an authenticated verdict.
        def load_user_from_session(session, env = nil)
          customer_session_verdict(session, env).customer
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
            # CustomDomain#identifier for :custom (DomainStrategy stash). The
            # logic layer needs it to rebuild the surface descriptor when it
            # mints a session itself (invite signup autologin, #4409).
            custom_domain_id: env['onetime.custom_domain_id'],
          }.merge(additional)
        end

        private

        # Whether THIS request already resolves a valid customer-session
        # identity. Used only by #credentialed_failure to decide whether a
        # rejected Authorization header should defer to the session. A
        # refused, MFA-pending, or unavailable verdict can only withhold.
        #
        # @param env [Hash, nil] Rack environment
        # @return [Boolean]
        def valid_session_identity?(env)
          return false unless env.is_a?(Hash)

          !load_user_from_session(env['rack.session'], env).nil?
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

# lib/onetime/application/auth_strategies/no_auth_strategy.rb
#
# frozen_string_literal: true

#
# Public strategy - allows all requests, loads customer from session if available.
#
# Routes: auth=noauth
# Access: Everyone (including authenticated)
# User: nil (anonymous) or authenticated Customer
#
# Exception — anonymous fallthrough refusal: on multi-strategy chains
# (auth=basicauth,noauth) a request that PRESENTED credentials which a
# credentialed strategy rejected must not degrade to anonymous. Otto's
# RouteAuthWrapper treats the chain as OR logic, so without this guard a
# request with invalid Basic credentials would succeed anonymously (silent
# 200 with null owner) instead of returning 401. The rejecting strategy
# records the failure in the Rack env (Helpers::CREDENTIALED_FAILURE_ENV_KEY)
# and this strategy refuses, making the whole chain fail closed.
# See docs/security/audits/2026-07-29-api.md item 1.
#
# The refusal is scoped to requests that would otherwise become ANONYMOUS.
# A session that resolves an identity wins over a rejected Authorization
# header, so a logged-in browser is never 401'd by a stale cached Basic
# credential or by a reverse proxy forwarding its own htpasswd header.
# That narrowing costs nothing: the audit hole was invalid credentials
# becoming anonymous, and a session-authenticated request is not anonymous.
#
# On noauth-ONLY routes no credentialed strategy runs, so an Authorization
# header (any scheme) is ignored and the request stays anonymous — refusing
# there would break deployments behind Basic-auth reverse proxies that
# forward the header, and browsers that re-send cached Basic credentials.
#
# @see Onetime::Application::AuthStrategies

require_relative 'helpers'

module Onetime
  module Application
    module AuthStrategies
      class NoAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        include Onetime::Application::OrganizationLoader

        @auth_method_name = 'noauth'

        class << self
          attr_reader :auth_method_name
        end

        def authenticate(env, _requirement)
          session = env['rack.session']

          # Try session first, then fall back to anonymous. Basic auth is
          # handled by a separate strategy in the route chain (routes.txt),
          # not here - this strategy only checks session state.
          cust = load_user_from_session(session)

          # Fail closed when this request presented credentials that a
          # credentialed strategy earlier in the chain already rejected
          # (auth=basicauth,noauth) AND the session resolved no identity of
          # its own — i.e. the request would otherwise proceed anonymously.
          # Echo the original failure reason so the resulting 401 tells the
          # caller their credentials were invalid rather than inventing a new
          # error.
          #
          # Checked AFTER load_user_from_session so a valid session cookie
          # outranks a stray Authorization header (browser-cached Basic
          # credentials, htpasswd-style reverse proxy forwarding its own
          # header); otherwise a logged-in user would 401 mid-session on
          # every basicauth,noauth route, including web-UI conceal.
          # Session-cookie failures never set this marker, so a logged-out or
          # stale session still degrades to anonymous rather than 401.
          if cust.nil?
            refused_reason = credentialed_failure_reason(env)
            return failure(refused_reason) if refused_reason
          end

          # Load organization context if user is authenticated
          org_context = if cust
                          load_organization_context(cust, session, env)
                        else
                          {}
                        end

          success(
            session: session,
            user: cust,  # nil for anonymous users
            auth_method: self.class.auth_method_name,
            **build_metadata(env, { organization_context: org_context }),
          )
        end
      end
    end
  end
end

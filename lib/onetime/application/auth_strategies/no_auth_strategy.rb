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
# Fail-closed on rejected credentials is enforced by Otto, not here: a
# credentialed strategy (BasicAuthStrategy et al.) that rejects an
# explicitly-presented Authorization header returns a TERMINAL AuthFailure,
# and Otto's RouteAuthWrapper halts the chain and fails closed (401)
# regardless of strategy order — so a request with invalid Basic credentials
# can no longer degrade to a silent anonymous 200 with a null owner. This
# strategy does no cross-strategy coordination of its own; it only resolves
# the session (or anonymous). See docs/security/audits/2026-07-29-api.md
# item 1 and Otto::Security::Authentication::AuthFailure.
#
# The one exception is deliberate: when the SAME request also resolves a valid
# session identity, the credentialed strategy makes its failure NON-terminal
# (Helpers#credentialed_failure), so the chain reaches this strategy and the
# session wins. A logged-in browser is therefore never 401'd by a stale cached
# Basic credential or a reverse-proxy-forwarded htpasswd header — the session
# outranks the stray Authorization header, exactly as before terminal
# AuthFailures replaced the env-marker guard.
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
          # not here - this strategy only checks session state. A rejected
          # Authorization header fails the chain closed via the credentialed
          # strategy's terminal AuthFailure (Otto's RouteAuthWrapper), so this
          # strategy never needs to refuse anonymous fallthrough itself.
          cust = load_user_from_session(session, env)

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

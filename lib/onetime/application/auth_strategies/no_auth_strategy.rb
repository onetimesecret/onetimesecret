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

          # Load organization context if user is authenticated
          org_context = if cust && !cust.anonymous?  # cust is nil for anonymous
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

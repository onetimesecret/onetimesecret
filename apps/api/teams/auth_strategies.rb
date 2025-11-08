# apps/api/teams/auth_strategies.rb

# Otto authentication strategies for Team API (apps/api/teams).
#
# This module implements strategies defined in Onetime::Application::AuthStrategies.
# All Team API endpoints require authentication (session or basic).
#
# Usage in routes file:
#   GET /api/teams/*   Controller#action auth=sessionauth

require 'onetime/application/auth_strategies'

module TeamAPI
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Registers noauth, session-based, and basic auth strategies.
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # NOTE: enable_authentication! is not needed - RouteAuthWrapper handles it
      # Authentication now happens via post-routing handler wrapping (not middleware)

      # Public routes - always available (anonymous or authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Check if authentication is enabled at initialization time
      unless Onetime::Application::AuthStrategies.authentication_enabled?
        OT.le '[TeamAPI::AuthStrategies] Authentication disabled in config - skipping session strategies'
        return
      end

      # Authenticated routes - require valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # HTTP Basic Auth - require valid apikey and apisecretkey
      otto.add_auth_strategy('basicauth', Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
    end
  end
end

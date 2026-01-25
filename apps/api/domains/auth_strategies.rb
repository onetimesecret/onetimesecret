# apps/api/domains/auth_strategies.rb
#
# frozen_string_literal: true

# Otto authentication strategies for Domains API (apps/api/domains).
#
# This module implements strategies defined in Onetime::Application::AuthStrategies.
# All Domains API endpoints require authentication and organization context.
#
# Usage in routes file:
#   GET /api/domains/*   Controller#action auth=sessionauth

require 'onetime/application/auth_strategies'

module DomainsAPI
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Registers session-based and HTTP Basic authentication strategies.
    # All domain operations require organization context.
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # NOTE: enable_authentication! is not needed - RouteAuthWrapper handles it
      # Authentication now happens via post-routing handler wrapping (not middleware)

      # Check if authentication is enabled at initialization time
      unless Onetime::Application::AuthStrategies.authentication_enabled?
        OT.le '[DomainsAPI::AuthStrategies] Authentication disabled in config - skipping session strategies'
        return
      end

      # Authenticated routes - require valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # HTTP Basic Auth - require valid apikey and apisecretkey
      otto.add_auth_strategy('basicauth', Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
    end
  end
end

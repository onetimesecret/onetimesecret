# apps/api/v2/auth_strategies.rb

# Otto authentication strategies for V2 API (apps/api/v2).
#
# This module implements strategies defined in Onetime::Application::AuthStrategies.
#
#
# Usage in routes file:
#   GET /api/v2/*   Controller#action auth=basicauth

require 'onetime/application/auth_strategies'

module V2
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      otto.enable_authentication!

      # Public routes - everyone allowed (including authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Authenticated routes - require valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # HTTP Basic Auth - require valid apikey and apisecretkey
      otto.add_auth_strategy('basicauth', Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
    end
  end
end

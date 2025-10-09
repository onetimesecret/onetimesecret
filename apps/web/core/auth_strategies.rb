# apps/web/core/auth_strategies.rb
#
# Otto authentication strategies for Web Core (apps/web/core).
#
# This module delegates to the centralized Onetime::Application::AuthStrategies
# for consistency across all applications.
#
# Usage in apps/web/core/application.rb:
#   Core::AuthStrategies.register_essential(router)
#
# Usage in routes file:
#   GET /public   Controller#action auth=noauth
#   GET /private  Controller#action auth=sessionauth
#   GET /colonel  Controller#action auth=colonelsonly
#
# Keep this code in sync with:
# @see docs/architecture/authentication.md#authstrategies

require 'onetime/application/auth_strategies'

module Core
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      otto.enable_authentication!

      # Public routes - allows everyone (anonymous or authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Authenticated routes - requires valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # Colonel routes - requires colonel role
      otto.add_auth_strategy('colonelsonly', Onetime::Application::AuthStrategies::ColonelStrategy.new)
    end
  end
end

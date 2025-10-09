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
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Always registers noauth strategy; only registers session-based strategies if enabled.
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      otto.enable_authentication!

      # Public routes - always available (anonymous or authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Check if authentication is enabled at initialization time
      unless Onetime::Application::AuthStrategies.authentication_enabled?
        OT.le "[Core::AuthStrategies] Authentication disabled in config - skipping session strategies"
        return
      end

      # Authenticated routes - requires valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # Colonel routes - requires colonel role
      otto.add_auth_strategy('colonelsonly', Onetime::Application::AuthStrategies::ColonelStrategy.new)
    end
  end
end

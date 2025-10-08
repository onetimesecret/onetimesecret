# apps/web/core/auth_strategies.rb

# Otto authentication strategies for Web Core (apps/web/core).
#
# This module delegates to the centralized Onetime::Application::AuthStrategies
# for consistency across all applications.
#
# Usage in apps/web/core/application.rb:
#   Core::AuthStrategies.register_all(router)
#
# Usage in routes file:
#   GET /public   Controller#action auth=publicly
#   GET /private  Controller#action auth=authenticated
#   GET /admin    Controller#action auth=colonel

module Core
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies
    #
    # @param otto [Otto] Otto router instance
    def register_all(otto)
      Onetime::Application::AuthStrategies.register_all(otto)
    end
  end
end

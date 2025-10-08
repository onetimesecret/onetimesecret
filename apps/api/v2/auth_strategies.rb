# apps/api/v2/auth_strategies.rb

# Otto authentication strategies for V2 API (apps/api/v2).
#
# This module delegates to the centralized Onetime::Application::AuthStrategies
# for consistency across all applications.
#
# Usage in apps/api/v2/application.rb:
#   V2::AuthStrategies.register_all(router)
#
# Usage in routes file:
#   GET /account   Controller#action auth=authenticated
#   GET /secret    Controller#action auth=publicly
#   GET /colonel   Controller#action auth=colonel

module V2
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

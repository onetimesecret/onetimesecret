# apps/api/v2/auth_strategies.rb

# Otto authentication strategies for V2 API (apps/api/v2).
#
# This module implements strategies defined in Onetime::Application::AuthStrategies.
#
#
# Usage in routes file:
#   GET /api/v2/*   Controller#action auth=basicauth

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

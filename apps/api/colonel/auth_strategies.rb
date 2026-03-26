# apps/api/colonel/auth_strategies.rb
#
# frozen_string_literal: true

module ColonelAPI
  module AuthStrategies
    include Onetime::Application::AuthStrategies

    def self.register_essential(router)
      # Register the colonel-specific authentication strategies
      router.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)
      router.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # HTTP Basic Auth - also auto-registers devbasicauth when DEV_BASIC_AUTH=true
      Onetime::Application::AuthStrategies.register_basic_auth(router)
    end
  end
end

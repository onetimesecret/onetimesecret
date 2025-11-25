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
      router.add_auth_strategy('basicauth', Onetime::Application::AuthStrategies::BasicAuthStrategy.new)
    end
  end
end

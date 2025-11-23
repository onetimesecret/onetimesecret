# apps/api/colonel/auth_strategies.rb
#
# frozen_string_literal: true

module ColonelAPI
  module AuthStrategies
    include Onetime::Application::AuthStrategies

    def self.register_essential(router)
      # Register the colonel-specific authentication strategies
      router.register_auth_strategy('noauth', Onetime::Application::NoAuthStrategy.new)
      router.register_auth_strategy('sessionauth', Onetime::Application::SessionAuthStrategy.new)
      router.register_auth_strategy('basicauth', Onetime::Application::BasicAuthStrategy.new)
    end
  end
end

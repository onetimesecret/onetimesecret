# apps/api/incoming/auth_strategies.rb
#
# frozen_string_literal: true

# Otto authentication strategies for Incoming API (apps/api/incoming).
#
# The Incoming API serves public endpoints for anonymous secret submission
# to pre-configured recipients. Only the noauth strategy is registered.
#
# Usage in routes file:
#   GET /incoming/*   Handler response=json auth=noauth

require 'onetime/application/auth_strategies'

module Incoming
  module AuthStrategies
    extend self

    # Registers authentication strategies with Otto router
    #
    # Only registers noauth since all Incoming API routes are public.
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # Public routes only - anonymous access
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)
    end
  end
end

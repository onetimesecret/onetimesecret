# apps/api/invite/auth_strategies.rb
#
# frozen_string_literal: true

# Otto authentication strategies for Invite API (apps/api/invite).
#
# This module implements strategies defined in Onetime::Application::AuthStrategies.
# Most endpoints use noauth (token validates access).
# Accept requires authentication (session-based).
#
# Usage in routes file:
#   GET  /api/invite/:token         noauth
#   POST /api/invite/:token/accept  auth=sessionauth
#   POST /api/invite/:token/decline noauth

require 'onetime/application/auth_strategies'

module InviteAPI
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Registers noauth and session-based strategies.
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # Public routes - always available (anonymous or authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Check if authentication is enabled at initialization time
      unless Onetime::Application::AuthStrategies.authentication_enabled?
        OT.le '[InviteAPI::AuthStrategies] Authentication disabled in config - skipping session strategies'
        return
      end

      # Authenticated routes - require valid session (for accept endpoint)
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)
    end
  end
end

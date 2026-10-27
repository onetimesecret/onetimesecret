# apps/api/v3/auth_strategies.rb
#
# frozen_string_literal: true

# Otto authentication strategies for V3 API (apps/api/v3).
#
# Registers strategies defined in Onetime::Application::AuthStrategies.
# Route declarations choose which registered strategies can authenticate.
#
#
# Usage in routes file:
#   GET /receipt/recent   V3::Logic::Secrets::ListReceipts auth=sessionauth,pasetoauth

require 'onetime/application/auth_strategies'

module V3
  module AuthStrategies
    extend self

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Always registers noauth; registers session, bearer-token and Basic auth
    # when account capabilities are enabled. Normal secret routes select
    # sessionauth, then pasetoauth (which accepts nothing until
    # auth.paseto.enabled is set).
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # NOTE: enable_authentication! is not needed - RouteAuthWrapper handles it
      # Authentication now happens via post-routing handler wrapping (not middleware)

      # Guest authentication stays registered when account features are disabled;
      # operation-level guest configuration still determines access.
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Check if account creation/usage is allowed at initialization time
      unless Onetime::Application::AuthStrategies.account_creation_allowed?
        OT.le '[V3::AuthStrategies] Authentication disabled in config - skipping session strategies'
        return
      end

      # Authenticated routes - require valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # Bearer tokens (PASETO v4.public, #2427) on the authenticated secret
      # routes and /version. Registered so the chains resolve; inert while
      # auth.paseto.enabled is off. Tokens are minted by POST /token.
      Onetime::Application::AuthStrategies.register_paseto_auth(otto, audience: Onetime::Paseto::V3_AUDIENCE)

      # Basic auth is registered for /version and /token, not normal secret operations.
      # Also auto-registers devbasicauth when DEV_BASIC_AUTH=true
      Onetime::Application::AuthStrategies.register_basic_auth(otto)
    end
  end
end

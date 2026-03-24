# apps/web/core/auth_strategies.rb
#
# frozen_string_literal: true

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
#   GET /colonel  Controller#action auth=sessionauth role=colonel
#
# Keep this code in sync with:
# @see docs/architecture/authentication.md#authstrategies

require 'onetime/application/auth_strategies'
require 'onetime/logger_methods'

module Core
  module AuthStrategies
    extend self
    extend Onetime::LoggerMethods

    # Registers Onetime authentication strategies with Otto router
    #
    # Delegates to centralized Onetime::Application::AuthStrategies.
    # Always registers noauth strategy; only registers session-based strategies if enabled.
    # For role-based authorization, use the role= route option (e.g., auth=sessionauth role=colonel).
    #
    # @param otto [Otto] Otto router instance
    def register_essential(otto)
      # NOTE: enable_authentication! is not needed - RouteAuthWrapper handles it
      # Authentication now happens via post-routing handler wrapping (not middleware)

      # Public routes - always available (anonymous or authenticated)
      otto.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)

      # Check if account creation/usage is allowed at initialization time
      unless Onetime::Application::AuthStrategies.account_creation_allowed?
        auth_logger.warn 'Authentication disabled in config - skipping session strategy registration',
          {
            module: 'Core::AuthStrategies',
          }
        return
      end

      # Authenticated routes - requires valid session
      otto.add_auth_strategy('sessionauth', Onetime::Application::AuthStrategies::SessionAuthStrategy.new)

      # Auto-register dev session strategy when enabled in config
      register_dev_session_auth(otto) if Onetime::Application::AuthStrategies.dev_session_auth_enabled?
    end

    # Registers development-only Session Auth strategy (opt-in, non-production only)
    #
    # Validates that authenticated sessions belong to dev_* users.
    # Normally called automatically by register_essential when config is set.
    #
    # @param otto [Otto] Otto router instance
    def register_dev_session_auth(otto)
      Onetime::Application::AuthStrategies.register_dev_session_auth(otto)
    end
  end
end

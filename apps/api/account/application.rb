# apps/api/account/application.rb

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module AccountAPI
  # Account API Application
  #
  # Internal API for site-only endpoints (account management, domains, etc).
  # These endpoints are not part of the public API and don't need versioning.
  # Serves JSON responses with native JSON types (leveraging Familia v2).
  #
  # ## Scope
  #
  # - Account management (profile, password, API tokens)
  # - Domain management (custom domains, branding)
  # - User's secret metadata (receipt/private endpoints)
  # - Colonel/admin endpoints
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Router: Otto (configured in BaseJSONAPI#build_router)
  # - Middleware: Universal (MiddlewareStack) + JSON API common (BaseJSONAPI)
  # - Authentication: Session-based and token-based strategies (most require auth)
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/account'.freeze

    def self.auth_strategy_module
      AccountAPI::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

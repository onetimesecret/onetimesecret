# apps/api/v3/application.rb

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module V3
  # V3 API Application
  #
  # RESTful API for Onetime Secret v3. Serves JSON responses with native
  # JSON types (numbers, booleans, null) instead of string-serialized values.
  # Uses Otto router for authentication and routing.
  #
  # ## Key Differences from V2
  #
  # - Returns native JSON types (leveraging Familia v2's JSON storage)
  # - Public API only (account/domain endpoints in separate Account API)
  # - Backward incompatible with v2 (breaking change in response format)
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Router: Otto (configured in BaseJSONAPI#build_router)
  # - Middleware: Universal (MiddlewareStack) + JSON API common (BaseJSONAPI)
  # - Authentication: Token-based and session-based strategies
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/v3'.freeze

    def self.auth_strategy_module
      V3::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

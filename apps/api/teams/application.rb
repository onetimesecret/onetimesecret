# apps/api/teams/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module TeamAPI
  # Team API Application
  #
  # Internal API for team management endpoints.
  # These endpoints are not part of the public API and don't need versioning.
  # Serves JSON responses with native JSON types (leveraging Familia v2).
  #
  # ## Scope
  #
  # - Team management (create, update, delete teams)
  # - Team member management (add, remove, list members)
  # - Team-based authorization and access control
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Router: Otto (configured in BaseJSONAPI#build_router)
  # - Middleware: Universal (MiddlewareStack) + JSON API common (BaseJSONAPI)
  # - Authentication: Session-based (sessionauth) and HTTP Basic (basicauth)
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/teams'.freeze

    warmup do
      # Empty warmup - just triggers the logging
    end

    def self.auth_strategy_module
      TeamAPI::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

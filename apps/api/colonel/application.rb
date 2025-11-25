# apps/api/colonel/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module ColonelAPI
  # Colonel API Application
  #
  # Administrative API for site-wide management and monitoring.
  # These endpoints are restricted to users with the 'colonel' role.
  #
  # ## Scope
  #
  # - Secret management (list, view, delete secrets)
  # - User management (list, view, modify user accounts)
  # - System monitoring (database metrics, Redis stats)
  # - IP address banning (block abusive IPs)
  # - Usage analytics and export
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Router: Otto (configured in BaseJSONAPI#build_router)
  # - Middleware: Universal (MiddlewareStack) + JSON API common (BaseJSONAPI)
  # - Authentication: Session-based (sessionauth)
  # - Authorization: Role-based (requires role='colonel')
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/colonel'

    warmup do
      # Empty warmup - just triggers the logging
    end

    def self.auth_strategy_module
      ColonelAPI::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

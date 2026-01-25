# apps/api/invite/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module InviteAPI
  # Invite API Application
  #
  # Public API for invitation token-based endpoints.
  # These endpoints handle invitation acceptance/decline flows.
  #
  # ## Scope
  #
  # - View invitation details (token validates)
  # - Accept invitation (requires authentication)
  # - Decline invitation (token validates)
  #
  # ## Authentication
  #
  # - GET  /api/invite/:token         - noauth (token validates)
  # - POST /api/invite/:token/accept  - sessionauth (user must be logged in)
  # - POST /api/invite/:token/decline - noauth (token validates)
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/invite'

    warmup do
      # Empty warmup - just triggers the logging
    end

    def self.auth_strategy_module
      InviteAPI::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

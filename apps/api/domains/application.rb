# apps/api/domains/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'logic'
require_relative 'auth_strategies'

module DomainsAPI
  # Domains API Application
  #
  # Internal API for custom domain management endpoints.
  # These endpoints are not part of the public API and don't need versioning.
  # Serves JSON responses with native JSON types (leveraging Familia v2).
  #
  # ## Scope
  #
  # - Custom domain management (create, update, delete domains)
  # - Domain verification (DNS TXT records, vhost configuration)
  # - Domain branding (logo, icon, brand settings)
  # - Organization-scoped domain ownership
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Router: Otto (configured in BaseJSONAPI#build_router)
  # - Middleware: Universal (MiddlewareStack) + JSON API common (BaseJSONAPI)
  # - Authentication: Session-based (sessionauth) and HTTP Basic (basicauth)
  # - Authorization: Organization-based (requires organization context)
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/domains'

    warmup do
      # Empty warmup - just triggers the logging
    end

    def self.auth_strategy_module
      DomainsAPI::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

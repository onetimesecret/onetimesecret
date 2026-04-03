# apps/api/incoming/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'auth_strategies'

# Load V2 logic helpers (UriHelpers used by Incoming::Logic::Base)
require_relative '../v2/logic/helpers'

# Load local Incoming logic classes
require_relative 'logic/incoming'

module Incoming
  # Incoming API Application
  #
  # Anonymous secret submission API for pre-configured recipients.
  # Follows V3 conventions: native JSON types, consistent field naming.
  # Mounted at /api/incoming, this API provides:
  #
  # - Configuration endpoint (available recipients)
  # - Secret submission to recipients
  # - Recipient validation
  #
  # ## Design Rationale
  #
  # These endpoints are separated from V2/V3 because:
  # 1. They are deployment-specific, not core secret lifecycle operations
  # 2. They can evolve independently of the versioned secrets API
  # 3. They serve a specialized use case (bug bounty, security reporting)
  #
  # ## Architecture
  #
  # - Inherits from BaseJSONAPI for common JSON API setup
  # - Uses Incoming::Logic classes for implementation
  # - All routes are public (noauth) since they serve anonymous users
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/api/incoming'

    warmup do
      # Empty warmup - just triggers the logging
    end

    def self.auth_strategy_module
      Incoming::AuthStrategies
    end

    def self.root_path
      __dir__
    end
  end
end

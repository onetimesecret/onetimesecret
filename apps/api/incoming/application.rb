# apps/api/incoming/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative '../base_json_api'
require_relative 'auth_strategies'

# Load V2 logic helpers that V3 depends on (V3::Logic::Base includes V2::Logic::UriHelpers)
require_relative '../v2/logic/helpers'

# Load V3 logic classes that we delegate to
require_relative '../v3/logic'

module Incoming
  # Incoming API Application
  #
  # Anonymous secret submission API for pre-configured recipients.
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
  # - Delegates to V3::Logic::Incoming classes for implementation (avoids duplication)
  # - All routes are public (noauth) since they serve anonymous users
  #
  class Application < BaseJSONAPI
    @uri_prefix = '/incoming'

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

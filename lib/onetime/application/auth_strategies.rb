# lib/onetime/application/auth_strategies.rb
#
# frozen_string_literal: true

#
# Centralized authentication strategies for Onetime applications.
# All applications (Web Core, V2 API, etc.) use these shared strategy classes.
#
# Structure:
#   auth_strategies/
#     helpers.rb                    - Shared helper methods
#     no_auth_strategy.rb           - Public access (auth=noauth)
#     base_session_auth_strategy.rb - Abstract base for session auth
#     session_auth_strategy.rb      - Authenticated sessions (auth=sessionauth)
#     basic_auth_strategy.rb        - HTTP Basic Auth (auth=basicauth)
#
# Keep this code in sync with:
# @see docs/architecture/authentication.md#authstrategies
#
# All dependent modules and references: `rg -t ruby -t markdown authstrategies`

require_relative 'organization_loader'
require_relative 'auth_strategies/helpers'
require_relative 'auth_strategies/no_auth_strategy'
require_relative 'auth_strategies/base_session_auth_strategy'
require_relative 'auth_strategies/session_auth_strategy'
require_relative 'auth_strategies/basic_auth_strategy'

module Onetime
  module Application
    module AuthStrategies
      extend self

      # Can users create and use accounts?
      #
      # Boot-time capability decision - called once during strategy
      # registration to determine whether to register sessionauth and
      # basicauth strategies with Otto. Uses strict `== true` because
      # enabling account capabilities is an explicit opt-in.
      #
      # Distinct from SessionHelpers#session_auth_enforced? which is
      # a per-request check using loose `!= false` comparison.
      #
      # @return [Boolean] true only if authentication is explicitly enabled
      def account_creation_allowed?
        settings = OT.conf&.dig('site', 'authentication')
        return false unless settings

        settings['enabled'] == true
      end

      # Registers core Onetime authentication strategies with Otto
      #
      # Registers session-based strategies (noauth, sessionauth).
      # For BasicAuth, call register_basic_auth(otto) separately.
      # For role-based authorization, use the role= route option (e.g., auth=sessionauth role=colonel).
      #
      # @param otto [Otto] Otto router instance
      def register_essential(otto)
        raise NotImplementedError, 'Please implement this method'
      end

      # Registers HTTP Basic Authentication strategy (opt-in)
      #
      # Only call this for apps that need API key authentication.
      # Reduces attack surface by not exposing Basic auth on all apps.
      #
      # @param otto [Otto] Otto router instance
      def register_basic_auth(otto)
        otto.add_auth_strategy('basicauth', BasicAuthStrategy.new)
      end
    end
  end
end

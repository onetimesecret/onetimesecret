# lib/onetime/application/auth_strategies.rb
#
# frozen_string_literal: true

#
# Centralized authentication strategies for Onetime applications.
# All applications (Web Core, V2 API, etc.) use these shared strategy classes.
#
# Structure:
#   auth_strategies/
#     helpers.rb                      - Shared helper methods
#     no_auth_strategy.rb             - Public access (auth=noauth)
#     base_session_auth_strategy.rb   - Abstract base for session auth
#     session_auth_strategy.rb        - Authenticated sessions (auth=sessionauth)
#     basic_auth_strategy.rb          - HTTP Basic Auth (auth=basicauth)
#     dev_basic_auth_strategy.rb      - Development-only Basic Auth (auth=devbasicauth)
#     dev_session_auth_strategy.rb    - Development-only Session Auth (auth=devsessionauth)
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
require_relative 'auth_strategies/dev_basic_auth_strategy'
require_relative 'auth_strategies/dev_session_auth_strategy'

module Onetime
  module Application
    module AuthStrategies
      extend self

      # Shared helper methods for authentication strategies
      module Helpers
        # Loads customer from session if authenticated
        #
        # @param session [Hash] Rack session
        # @return [Onetime::Customer, nil] Customer if found, nil otherwise
        def load_user_from_session(session)
          return nil unless session
          return nil unless session['authenticated'] == true

          external_id = session['external_id']
          return nil if external_id.to_s.empty?

          Onetime::Customer.find_by_extid(external_id)
        rescue StandardError => ex
          OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
          OT.ld ex.backtrace.first(3).join("\n")
          nil
        end

        # Builds standard metadata hash from env
        #
        # @param env [Hash] Rack environment
        # @param additional [Hash] Additional metadata to merge
        # @return [Hash] Metadata hash
        def build_metadata(env, additional = {})
          {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT'],
            domain_strategy: env['onetime.domain_strategy'],
            display_domain: env['onetime.display_domain'],
          }.merge(additional)
        end
      end

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
      # Also auto-registers devbasicauth when development.devbasicauth config is true.
      #
      # @param otto [Otto] Otto router instance
      def register_basic_auth(otto)
        otto.add_auth_strategy('basicauth', BasicAuthStrategy.new)

        # Auto-register dev strategy when enabled in config
        register_dev_basic_auth(otto) if dev_basic_auth_enabled?
      end

      # Check if development basic auth is enabled
      #
      # Checks config first, falls back to DEV_BASIC_AUTH env var.
      # Config example: `devbasicauth: <%= ENV['DEV_BASIC_AUTH'] == 'true' %>`
      #
      # @return [Boolean] true if enabled via config or env var
      def dev_basic_auth_enabled?
        # Config takes precedence (supports ERB: <%= ENV['DEV_BASIC_AUTH'] == 'true' %>)
        config_value = OT.conf&.dig('development', 'devbasicauth')
        return config_value == true if [true, false].include?(config_value)

        # Fallback to env var directly
        ENV['DEV_BASIC_AUTH'] == 'true'
      end

      # Registers development-only Basic Auth strategy (opt-in, non-production only)
      #
      # Auto-provisions ephemeral dev users with dev_* prefixed credentials.
      # Users expire after 20 hours. BLOCKED in production environments.
      #
      # Normally called automatically by register_basic_auth when config is set.
      # Can also be called directly for explicit registration.
      #
      # @param otto [Otto] Otto router instance
      # @raise [SecurityError] if called in production
      # @see DevBasicAuthStrategy
      # @see https://github.com/onetimesecret/onetimesecret/issues/2735
      def register_dev_basic_auth(otto)
        DevBasicAuthStrategy.production_guard!
        otto.add_auth_strategy('devbasicauth', DevBasicAuthStrategy.new)
        OT.li "[auth_strategies] Registered devbasicauth (TTL: #{DevBasicAuthStrategy::DEV_CUSTOMER_TTL / 3600}h)"
      end

      # Check if development session auth is enabled
      #
      # Checks config first, falls back to DEV_SESSION_AUTH env var.
      # Config example: `devsessionauth: <%= ENV['DEV_SESSION_AUTH'] == 'true' %>`
      #
      # @return [Boolean] true if enabled via config or env var
      def dev_session_auth_enabled?
        # Config takes precedence (supports ERB: <%= ENV['DEV_SESSION_AUTH'] == 'true' %>)
        config_value = OT.conf&.dig('development', 'devsessionauth')
        return config_value if [true, false].include?(config_value)

        # Fallback to env var directly
        ENV['DEV_SESSION_AUTH'] == 'true'
      end

      # Registers development-only Session Auth strategy (opt-in, non-production only)
      #
      # Validates that authenticated sessions belong to dev_* users.
      # BLOCKED in production environments.
      #
      # @param otto [Otto] Otto router instance
      # @raise [SecurityError] if called in production
      # @see DevSessionAuthStrategy
      # @see https://github.com/onetimesecret/onetimesecret/issues/2735
      def register_dev_session_auth(otto)
        DevSessionAuthStrategy.production_guard!
        otto.add_auth_strategy('devsessionauth', DevSessionAuthStrategy.new)
        OT.li '[auth_strategies] Registered devsessionauth'
      end
    end
  end
end

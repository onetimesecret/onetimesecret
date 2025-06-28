# lib/onetime/services/system/authentication.rb

require 'onetime/refinements/indifferent_hash_access'

require_relative '../service_provider'

module Onetime
  module Services
    module System
      ##
      # Authentication Provider
      #
      # Configures authentication settings including colonels (admin users),
      # authentication modes, and validation of authentication configuration.
      # Ensures authentication settings are properly validated and available
      # system-wide.
      #
      class AuthenticationProvider < ServiceProvider
        using Onetime::IndifferentHashAccess

        attr_reader :colonels, :auth_config

        def initialize
          super(:authentication, type: TYPE_CONFIG, priority: 25)
        end

        ##
        # Configure authentication settings from site configuration
        #
        # @param config [Hash] Application configuration
        def start(config)
          debug('Configuring authentication settings...')

          site_config  = config.fetch(:site, {})
          @auth_config = site_config.fetch(:authentication, {})

          # Extract colonels (admin users) configuration
          @colonels = @auth_config.fetch(:colonels, [])

          # Validate authentication configuration
          validate_auth_config

          # Register authentication state in ServiceRegistry
          set_state(:colonels, @colonels)
          set_state(:auth_config, @auth_config)
          set_state(:authentication_enabled, authentication_enabled?)

          log_auth_status
        end

        ##
        # Check if authentication is enabled
        #
        # @return [Boolean] true if authentication is enabled
        def authentication_enabled?
          !feature_disabled?(@auth_config)
        end

        ##
        # Health check for authentication provider
        #
        # @return [Boolean] true if authentication is properly configured
        def healthy?
          super && !@auth_config.nil?
        end

        private

        def validate_auth_config
          # Warn if no colonels are configured
          if @colonels.empty?
            warn('Warning: No colonels (admin users) configured')
          else
            debug("Configured colonels: #{@colonels.join(', ')}")
          end

          # Validate authentication settings consistency
          if authentication_enabled? && @auth_config.empty?
            warn('Warning: Authentication enabled but no configuration provided')
          end
        end

        def log_auth_status
          if authentication_enabled?
            debug("Authentication enabled with #{@colonels.size} colonel(s)")
          else
            debug('Authentication disabled')
          end
        end

        def feature_disabled?(config)
          # Check if feature is explicitly disabled
          config.is_a?(Hash) && config[:enabled] == false
        end
      end

      # Legacy method for backward compatibility
      def setup_authentication(config)
        provider = AuthenticationProvider.new
        provider.start_internal(config)
        provider
      end
    end
  end
end

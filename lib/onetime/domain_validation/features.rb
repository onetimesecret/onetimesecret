# lib/onetime/domain_validation/features.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # Features - Unified configuration accessor for domain validation.
    #
    # Design Decision: Class with class-level state (mutable accessors).
    #
    # Centralized configuration accessor for domain validation features.
    # but centralizes all domain-related config in one place. The class-level
    # state is set once at boot by the ConfigureDomains initializer.
    #
    # For testing, you can stub the class methods directly or use the
    # `configure` class method to set all values atomically.
    #
    # Configuration source: OT.conf.dig('features', 'domains', ...)
    #
    # Usage:
    #   # At boot (via initializer)
    #   Onetime::DomainValidation::Features.configure(
    #     strategy_name: 'approximated',
    #     api_key: 'xxx',
    #     proxy_ip: '1.2.3.4',
    #     ...
    #   )
    #
    #   # At runtime
    #   Features.api_key         # => 'xxx'
    #   Features.strategy_name   # => 'approximated'
    #   Features.safe_dump       # => Hash for API responses
    #
    class Features
      # Class-level state - set once at boot, read many times
      @strategy_name = nil
      @api_key       = nil
      @proxy_ip      = nil
      @proxy_host    = nil
      @proxy_name    = nil
      @vhost_target  = nil

      class << self
        attr_accessor :strategy_name,
          :api_key,
          :proxy_ip,
          :proxy_host,
          :proxy_name,
          :vhost_target

        # Atomic configuration - sets all values at once.
        # Useful for initializers and testing.
        #
        # @param strategy_name [String, nil] Validation strategy (approximated, passthrough, caddy_on_demand)
        # @param api_key [String, nil] Approximated API key
        # @param proxy_ip [String, nil] IP address of the Approximated proxy
        # @param proxy_host [String, nil] Hostname of the Approximated proxy
        # @param proxy_name [String, nil] Human-readable proxy name
        # @param vhost_target [String, nil] Target address for vhost creation
        #
        def configure(strategy_name: nil, api_key: nil, proxy_ip: nil,
                      proxy_host: nil, proxy_name: nil, vhost_target: nil)
          @strategy_name = strategy_name
          @api_key       = api_key
          @proxy_ip      = proxy_ip
          @proxy_host    = proxy_host
          @proxy_name    = proxy_name
          @vhost_target  = vhost_target
        end

        # Reset all configuration to nil.
        # Primarily for testing isolation.
        #
        def reset!
          configure(
            strategy_name: nil,
            api_key: nil,
            proxy_ip: nil,
            proxy_host: nil,
            proxy_name: nil,
            vhost_target: nil,
          )
        end

        # Load configuration from the application config hash.
        #
        # @param config [Hash] Application configuration (typically OT.conf)
        # @return [void]
        #
        def load_from_config(config)
          domains_config = config.dig('features', 'domains') || {}
          approx_config  = domains_config['approximated'] || {}

          configure(
            strategy_name: domains_config['validation_strategy'] || 'passthrough',
            api_key: approx_config['api_key'],
            proxy_ip: approx_config['proxy_ip'],
            proxy_host: approx_config['proxy_host'],
            proxy_name: approx_config['proxy_name'],
            vhost_target: approx_config['vhost_target'],
          )
        end

        # Check if the Approximated API is configured.
        #
        # @return [Boolean] true if api_key is present
        #
        def api_configured?
          !api_key.to_s.empty?
        end

        # Check if using Approximated strategy.
        #
        # @return [Boolean]
        #
        def approximated?
          strategy_name&.downcase == 'approximated'
        end

        # Safe dump of configuration for API responses.
        # Excludes sensitive data (api_key).
        #
        # @return [Hash] Configuration data safe for client exposure
        #
        def safe_dump
          {
            type: strategy_name,          # Legacy field name for compatibility
            proxy_ip: proxy_ip,
            proxy_name: proxy_name,
            proxy_host: proxy_host,
            vhost_target: vhost_target,
            validation_strategy: strategy_name || 'passthrough',
          }
        end

        # Returns non-empty configuration keys for logging.
        #
        # @return [Array<Symbol>] List of configured (non-nil, non-empty) settings
        #
        def configured_settings
          settings = {
            strategy_name: strategy_name,
            api_key: api_key,
            proxy_ip: proxy_ip,
            proxy_host: proxy_host,
            proxy_name: proxy_name,
            vhost_target: vhost_target,
          }

          settings.reject { |_k, v| v.to_s.empty? }.keys
        end
      end
    end
  end
end

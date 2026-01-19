# lib/onetime/domain_validation/features.rb
#
# frozen_string_literal: true

module Onetime
  module DomainValidation
    # Features - Unified configuration accessor for domain validation.
    #
    # Design Decision: Class with class-level state (mutable accessors).
    #
    # This mirrors the existing Cluster::Features pattern for compatibility
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
    #     cluster_ip: '1.2.3.4',
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
      @cluster_ip    = nil
      @cluster_host  = nil
      @cluster_name  = nil
      @vhost_target  = nil

      class << self
        attr_accessor :strategy_name,
          :api_key,
          :cluster_ip,
          :cluster_host,
          :cluster_name,
          :vhost_target

        # Atomic configuration - sets all values at once.
        # Useful for initializers and testing.
        #
        # @param strategy_name [String, nil] Validation strategy (approximated, passthrough, caddy_on_demand)
        # @param api_key [String, nil] Approximated API key
        # @param cluster_ip [String, nil] IP address of the cluster
        # @param cluster_host [String, nil] Hostname of the cluster
        # @param cluster_name [String, nil] Human-readable cluster name
        # @param vhost_target [String, nil] Target address for vhost creation
        #
        def configure(strategy_name: nil, api_key: nil, cluster_ip: nil,
                      cluster_host: nil, cluster_name: nil, vhost_target: nil)
          @strategy_name = strategy_name
          @api_key       = api_key
          @cluster_ip    = cluster_ip
          @cluster_host  = cluster_host
          @cluster_name  = cluster_name
          @vhost_target  = vhost_target
        end

        # Reset all configuration to nil.
        # Primarily for testing isolation.
        #
        def reset!
          configure(
            strategy_name: nil,
            api_key: nil,
            cluster_ip: nil,
            cluster_host: nil,
            cluster_name: nil,
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
          cluster_config = domains_config['cluster'] || {}

          configure(
            strategy_name: domains_config['strategy'] || 'passthrough',
            api_key: cluster_config['api_key'],
            cluster_ip: cluster_config['cluster_ip'],
            cluster_host: cluster_config['cluster_host'],
            cluster_name: cluster_config['cluster_name'],
            vhost_target: cluster_config['vhost_target'],
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
            cluster_ip: cluster_ip,
            cluster_name: cluster_name,
            cluster_host: cluster_host,
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
            cluster_ip: cluster_ip,
            cluster_host: cluster_host,
            cluster_name: cluster_name,
            vhost_target: vhost_target,
          }

          settings.reject { |_k, v| v.to_s.empty? }.keys
        end
      end
    end
  end
end

# lib/onetime/initializers/configure_domains.rb
#
# frozen_string_literal: true

require_relative '../domain_validation/features'

module Onetime
  module Initializers
    # ConfigureDomains initializer
    #
    # Configures custom domains feature if enabled. Populates
    # DomainValidation::Features with configuration values from config file.
    #
    # Runtime state set:
    # - Onetime::Runtime.features.domains_enabled
    # - Onetime::DomainValidation::Features.* (all config values)
    #
    class ConfigureDomains < Onetime::Boot::Initializer
      @provides = [:domains]

      def execute(_context)
        domains_config = OT.conf.dig('features', 'domains') || {}

        is_enabled = domains_config['enabled'].to_s == 'true'

        # Set runtime state
        Onetime::Runtime.update_features(domains_enabled: is_enabled)

        return app_logger.debug '[init] Domains feature disabled' unless is_enabled

        # Configure DomainValidation::Features from config
        # This is the canonical source of domain validation configuration
        klass = Onetime::DomainValidation::Features
        klass.load_from_config(OT.conf)

        configured_settings = klass.configured_settings
        app_logger.debug "[init] ConfigureDomains #{configured_settings}"

        unless klass.api_configured?
          app_logger.debug "No domain cluster api key configured (strategy: #{klass.strategy_name})"
        end
      end
    end
  end
end

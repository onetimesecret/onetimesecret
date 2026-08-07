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
      @depends_on = [:familia_config]
      @provides   = [:domains]

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

        warn_if_default_shadows_custom_domain(domains_config['default'], OT.conf.dig('site', 'host'))
      end

      # Boot-time drift guard (companion to CustomDomain.overlaps_canonical_domain?,
      # #3841): registration blocks new domains that collide with canonical hosts,
      # but nothing stops an operator from later pointing features.domains.default
      # at an ALREADY-REGISTERED custom domain. Requests to that host classify
      # :canonical before the custom-domain lookup, so its per-domain brand and
      # signin configuration silently never apply. Advisory only: never changes
      # classification and never fails boot (Redis may be unavailable here).
      # Runs here (once per boot) rather than in the DomainStrategy middleware,
      # which initializes once per mounted app, and uses the display_domain
      # index lookup rather than hydrating the full record.
      def warn_if_default_shadows_custom_domain(default_host, site_host)
        return if default_host.to_s.empty?
        return if default_host == site_host
        return if Onetime::CustomDomain.resolve_domain_id(default_host).nil?

        OT.le "[init] ConfigureDomains: features.domains.default #{default_host.inspect} " \
              'is a registered custom domain; its per-domain brand/signin configuration will be ' \
              'IGNORED on requests to this host because it classifies as :canonical. ' \
              'Unset features.domains.default or remove the custom domain registration.'
      rescue StandardError => ex
        app_logger.debug "[init] ConfigureDomains drift check skipped: #{ex.class}: #{ex.message}"
      end
    end
  end
end

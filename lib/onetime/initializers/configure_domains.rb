# lib/onetime/initializers/configure_domains.rb
#
# frozen_string_literal: true

require_relative '../domain_validation/features'
require_relative '../utils/canonical_hosts'

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

        site_host = OT.conf.dig('site', 'host')
        warn_if_default_shadows_custom_domain(domains_config['default'], site_host)
        warn_if_link_pool_shadows_custom_domains(
          domains_config['link_domains'], domains_config['default'], site_host
        )
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

      # Same drift guard, applied to the operator link pool
      # (features.domains.link_domains, #4063).
      #
      # Every pool member joins the canonical host set, and the exact-match
      # :canonical arm in Chooserator outranks the custom-domain lookup — so
      # listing a host a tenant has already registered shadows that record in
      # exactly the way `default` does: the operator's host wins
      # classification and the tenant's per-domain brand/signin configuration
      # silently stops applying. One warn line per shadowed host.
      #
      # Reads the pool through Utils::CanonicalHosts.link_pool rather than
      # Middleware::DomainStrategy.link_domains: the middleware resolves its
      # pool in #initialize_from_config, which runs when a Rack app is built,
      # i.e. after every boot initializer. At this point DomainStrategy holds
      # nil (or state left over from a previous boot in-process).
      #
      # Deliberately keeps the fail-open shape of the sibling guard: the
      # blanket rescue downgrades to a debug log (Redis may be unavailable
      # here) and this never fails boot. The #execute early return when
      # domains are disabled gates this too, which is correct for an advisory
      # — a disabled feature shadows nothing. The set-but-empty LINK_DOMAINS
      # boot error belongs in Config.raise_concerns, NOT here: anything
      # raised inside this method is swallowed by the rescue below.
      #
      # @param link_hosts [Array<String>, nil] raw features.domains.link_domains
      # @param default_host [String, nil] features.domains.default (already
      #   covered by warn_if_default_shadows_custom_domain, which owns its
      #   own message)
      # @param site_host [String, nil] site.host
      def warn_if_link_pool_shadows_custom_domains(link_hosts, default_host, site_host)
        # link_pool resolves an unset pool to [primary], so with LINK_DOMAINS
        # unset every candidate is filtered out below and this is a no-op.
        pool = Onetime::Utils::CanonicalHosts.link_pool(link_hosts: link_hosts)
        seen = [default_host, site_host].filter_map { |host| normalize_host(host) }

        pool.each do |configured|
          # Normalized (lowercased, port-stripped) because that is the form
          # the display_domain index is keyed by; a 'Go.Example.com' entry
          # would otherwise miss its own registration and warn nothing.
          host = normalize_host(configured)
          next if host.nil? || seen.include?(host)

          seen << host
          next if Onetime::CustomDomain.resolve_domain_id(host).nil?

          OT.le "[init] ConfigureDomains: features.domains.link_domains member #{host.inspect} " \
                'is a registered custom domain; its per-domain brand/signin configuration will be ' \
                'IGNORED on requests to this host because it classifies as :canonical. ' \
                'Remove it from LINK_DOMAINS or remove the custom domain registration.'
        end
      rescue StandardError => ex
        app_logger.debug "[init] ConfigureDomains link pool drift check skipped: #{ex.class}: #{ex.message}"
      end

      private

      def normalize_host(host)
        Onetime::Utils::DomainParser.extract_hostname(host.to_s.strip)
      end
    end
  end
end

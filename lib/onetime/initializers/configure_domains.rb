# lib/onetime/initializers/configure_domains.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # ConfigureDomains initializer
    #
    # Configures custom domains feature if enabled. Sets up cluster configuration
    # for domain management via OT::Cluster::Features class variables.
    #
    # Runtime state set:
    # - Onetime::Runtime.features.domains_enabled
    #
    class ConfigureDomains < Onetime::Boot::Initializer
      @provides = [:domains]

      def execute(_context)
        domains_config = OT.conf.dig('features', 'domains') || {}

        is_enabled = domains_config['enabled'].to_s == 'true'

        # Set runtime state
        Onetime::Runtime.update_features(domains_enabled: is_enabled)

        return app_logger.debug '[init] Domains feature disabled' unless is_enabled

        cluster            = domains_config['cluster']
        non_empty_settings = cluster.reject { _2.to_s.empty? }.keys

        app_logger.debug "[init] ConfigureDomains #{non_empty_settings}"

        # Configure OT::Cluster::Features class variables
        klass              = OT::Cluster::Features
        klass.api_key      = cluster['api_key']
        klass.cluster_ip   = cluster['cluster_ip']
        klass.cluster_name = cluster['cluster_name']
        klass.cluster_host = cluster['cluster_host']
        klass.vhost_target = cluster['vhost_target']

        unless klass.api_key
          app_logger.debug "No `site.domains.cluster` api key (#{klass.api_key})"
        end
      end
    end
  end
end

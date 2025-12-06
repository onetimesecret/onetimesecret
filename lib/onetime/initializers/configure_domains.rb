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
        is_enabled = OT.conf.dig('features', 'domains', 'enabled').to_s == 'true'

        unless is_enabled
          OT.ld '[init] Domains feature disabled'
          Onetime::Runtime.update_features(domains_enabled: false)
          return
        end

        cluster = OT.conf.dig('features', 'domains', 'cluster')
        OT.ld "[init] Setting OT::Cluster::Features #{cluster}"

        # Configure OT::Cluster::Features class variables
        klass              = OT::Cluster::Features
        klass.api_key      = cluster['api_key']
        klass.cluster_ip   = cluster['cluster_ip']
        klass.cluster_name = cluster['cluster_name']
        klass.cluster_host = cluster['cluster_host']
        klass.vhost_target = cluster['vhost_target']

        OT.ld "[init] Domains config: #{cluster}"

        unless klass.api_key
          raise OT::Problem.new, "No `site.domains.cluster` api key (#{klass.api_key})"
        end

        # Set runtime state
        Onetime::Runtime.update_features(domains_enabled: true)
      end
    end
  end
end

# lib/onetime/initializers/configure_domains.rb

module Onetime
  module Initializers

    def configure_domains
      is_enabled = conf.dig(:site, :domains, :enabled).to_s == 'true'
      return unless is_enabled

      cluster = conf.dig(:site, :domains, :cluster)
      OT.ld "Setting OT::Cluster::Features #{cluster}"
      klass = OT::Cluster::Features
      klass.api_key = cluster[:api_key]
      klass.cluster_ip = cluster[:cluster_ip]
      klass.cluster_name = cluster[:cluster_name]
      klass.cluster_host = cluster[:cluster_host]
      klass.vhost_target = cluster[:vhost_target]
      OT.ld "Domains config: #{cluster}"
      unless klass.api_key
        raise OT::Problem.new, "No `site.domains.cluster` api key (#{klass.api_key})"
      end
    end

  end
end

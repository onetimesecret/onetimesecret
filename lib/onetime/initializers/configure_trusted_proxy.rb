# lib/onetime/initializers/configure_trusted_proxy.rb
#
# frozen_string_literal: true

require 'ipaddr'
require 'rack/request'

module Onetime
  module Initializers
    # ConfigureTrustedProxy initializer
    #
    # Configures Rack::Request's built-in IP resolution to handle deployments
    # behind reverse proxies (Kubernetes ingress, cloud load balancers, etc.).
    #
    # Configuration (etc/config.yaml or config.defaults.yaml):
    #   site.trusted_proxy_depth:
    #     0 = don't trust forwarded headers (default, safe for direct exposure)
    #     1+ = trust forwarded headers; Rack filters out RFC1918 proxy IPs
    #
    #   site.trusted_proxy_cidrs: (optional)
    #     Additional CIDR ranges to trust as proxies beyond RFC1918 defaults.
    #     Example: ["203.0.113.0/24", "2001:db8::/32"]
    #
    # How it works:
    #   - depth=0: Disables X-Forwarded-For/Forwarded parsing entirely
    #   - depth>0: Rack walks headers in reverse, skipping IPs matching ip_filter
    #   - Rack's default ip_filter already trusts 10.x, 172.16-31.x, 192.168.x, etc.
    #
    class ConfigureTrustedProxy < Onetime::Boot::Initializer
      @provides = [:trusted_proxy]

      def execute(_context)
        site_config  = OT.conf['site'] || {}
        depth        = site_config['trusted_proxy_depth'].to_i
        custom_cidrs = Array(site_config['trusted_proxy_cidrs'])

        if depth <= 0
          # Don't trust any forwarded headers - use REMOTE_ADDR only
          Rack::Request.forwarded_priority = []
          app_logger.debug '[init] Trusted proxy disabled (depth=0), using REMOTE_ADDR only'
          return
        end

        # depth > 0: Trust forwarded headers
        # Rack's default ip_filter handles RFC1918 ranges automatically.
        # Configure header priority based on trusted_ip_header setting.
        header_pref                      = site_config['trusted_ip_header'] || 'X-Forwarded-For'
        Rack::Request.forwarded_priority = header_priority_for(header_pref)

        # Add custom trusted CIDRs if configured
        if custom_cidrs.any?
          configure_custom_cidrs(custom_cidrs)
        end

        app_logger.debug "[init] Trusted proxy enabled: header=#{header_pref}, custom_cidrs=#{custom_cidrs.size}"
      end

      private

      def header_priority_for(header_pref)
        case header_pref
        when 'Forwarded'
          [:forwarded]
        when 'Both'
          [:forwarded, :x_forwarded]
        else
          [:x_forwarded]
        end
      end

      def configure_custom_cidrs(cidrs)
        parsed_ranges = cidrs.filter_map do |cidr|
          IPAddr.new(cidr)
        rescue IPAddr::InvalidAddressError => ex
          app_logger.warn "[init] Invalid trusted_proxy_cidr '#{cidr}': #{ex.message}"
          nil
        end

        return if parsed_ranges.empty?

        # Extend Rack's default filter to also trust the configured CIDRs.
        #
        # Hot path: invoked once per forwarded-header hop on every request.
        # Two perf-relevant choices:
        #
        #   1. Parse `ip` once, up front. IPAddr#include?(String) coerces via
        #      IPAddr.new on every call, so N ranges would mean N parses.
        #      Hoisting the parse turns this into 1 parse + N integer compares.
        #
        #   2. Rescue is narrowed to IPAddr::InvalidAddressError. Malformed IPs
        #      are expected input — `ip` may be REMOTE_ADDR (trusted) or any
        #      hop value from an attacker-controlled X-Forwarded-For/Forwarded
        #      header. Anything other than InvalidAddressError (NoMethodError,
        #      etc.) is a real bug and should surface, not be masked as "not
        #      trusted".
        #
        # No per-request logging by design. Because `ip` can come from a
        # forwarded header, anything emitted here is an attacker-controlled
        # log-flood vector. Boot-time validation above already reports
        # malformed CIDRs from config, which is the actionable case.
        default_filter          = Rack::Request.ip_filter
        Rack::Request.ip_filter = ->(ip) do
          return true if default_filter.call(ip)

          parsed_ip = IPAddr.new(ip)
          parsed_ranges.any? { it.include?(parsed_ip) }
        rescue IPAddr::InvalidAddressError
          false
        end
      end
    end
  end
end

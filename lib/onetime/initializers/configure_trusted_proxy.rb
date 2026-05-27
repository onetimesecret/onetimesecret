# lib/onetime/initializers/configure_trusted_proxy.rb
#
# frozen_string_literal: true

require 'ipaddr'
require 'rack/request'

module Onetime
  module Initializers
    # ConfigureTrustedProxy initializer
    #
    # Configures Rack::Request's IP resolution for deployments behind reverse
    # proxies (Kubernetes ingress, cloud load balancers, CDNs, etc.).
    #
    # Configuration (etc/config.yaml or config.defaults.yaml):
    #
    #   site:
    #     network:
    #       trusted_proxy:
    #         enabled: true/false
    #         mode: filter/depth
    #         header: X-Forwarded-For/Forwarded/Both
    #         cidrs: []      # filter mode: additional CIDRs beyond RFC1918
    #         depth: 1       # depth mode: hops to skip from right
    #
    # Modes:
    #   - 'filter' (default): Rack walks X-Forwarded-For right-to-left, skipping
    #     RFC1918 (10.x, 172.16-31.x, 192.168.x) automatically. Returns first
    #     non-private IP. Add non-RFC1918 proxy ranges via `cidrs`.
    #
    #   - 'depth': Position-based counting. Skip exactly N rightmost hops.
    #     Use when: CDN has public IP, variable proxy depth, or you need
    #     deterministic hop selection regardless of IP class.
    #
    # Backwards compatibility:
    #   Falls back to legacy config (site.trusted_proxy_depth) if new structure
    #   is not present. Legacy depth>0 maps to filter mode.
    #
    class ConfigureTrustedProxy < Onetime::Boot::Initializer
      @provides = [:trusted_proxy]

      def execute(_context)
        config = load_config

        # No-op if trusted proxy support is not enabled. This allows us to avoid
        # changing default Rack behavior that trusts X-Forwarded-For when
        # REMOTE_ADDR is private (according to RFC1918).
        #
        # Log the disabled path explicitly: when ops debug "why does my IP look
        # wrong behind Cloudflare?", the first thing to check is whether this
        # initializer fired. A silent return leaves them guessing.
        unless config && config[:enabled]
          app_logger.info 'Trusted proxy disabled; Rack::Request#ip will use REMOTE_ADDR',
            configured: !config.nil?
          return
        end

        app_logger.info 'Trusted proxy enabled',
          mode: config[:mode],
          header: config[:header],
          cidrs: config[:cidrs],
          depth: config[:depth]

        case config[:mode]
        when 'depth'
          configure_depth_mode(config)
        else
          configure_filter_mode(config)
        end
      end

      private

      def load_config
        trusted_proxy = OT.conf.dig('site', 'network', 'trusted_proxy') || {}
        return unless trusted_proxy.key?('enabled')

        {
          enabled: trusted_proxy['enabled'] == true,
          mode: trusted_proxy['mode'] || 'filter',
          header: trusted_proxy['header'] || 'X-Forwarded-For',
          cidrs: Array(trusted_proxy['cidrs']),
          depth: trusted_proxy['depth'].to_i.clamp(1, 10),
        }
      end

      # Filter mode: Rack's built-in IP-based filtering
      #
      # Rack walks X-Forwarded-For right-to-left, skipping IPs that match
      # ip_filter (RFC1918 by default). Returns first non-matching IP.
      def configure_filter_mode(config)
        Rack::Request.forwarded_priority = header_priority_for(config[:header])

        if config[:cidrs].any?
          configure_custom_cidrs(config[:cidrs])
        end

        app_logger.info 'Configured trusted proxy filter mode',
          header: config[:header],
          forwarded_priority: Rack::Request.forwarded_priority,
          custom_cidrs: config[:cidrs].size
      end

      # Depth mode: Position-based counting
      #
      # Disables Rack's built-in parsing and overrides Rack::Request#ip
      # to use ClientIpHelpers.extract with explicit hop counting.
      def configure_depth_mode(config)
        # Disable Rack's forwarded header parsing
        Rack::Request.forwarded_priority = []

        depth  = config[:depth]
        header = config[:header]

        # Override Rack::Request#ip to use position-based extraction
        Rack::Request.class_eval do
          define_method(:ip) do
            Onetime::ClientIpHelpers.extract(env, depth: depth, header: header)
          end
        end

        app_logger.info 'Configured trusted proxy depth mode',
          header: header,
          depth: depth
      end

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
          app_logger.warn 'Invalid trusted_proxy CIDR; skipping',
            cidr: cidr,
            error: ex.message
          nil
        end

        if parsed_ranges.empty?
          app_logger.warn 'No valid trusted_proxy CIDRs registered; default RFC1918 filter unchanged',
            requested: cidrs
          return
        end

        # Extend Rack's default filter to also trust the configured CIDRs.
        #
        # Hot path: invoked once per forwarded-header hop on every request.
        # Parse `ip` once up front — IPAddr#include?(String) coerces via
        # IPAddr.new on every call, so N ranges would mean N parses.
        default_filter          = Rack::Request.ip_filter
        Rack::Request.ip_filter = ->(ip) do
          return true if default_filter.call(ip)

          parsed_ip = IPAddr.new(ip)
          parsed_ranges.any? { it.include?(parsed_ip) }
        rescue IPAddr::InvalidAddressError
          false
        end

        app_logger.info 'Extended Rack::Request.ip_filter with custom trusted_proxy CIDRs',
          registered: parsed_ranges.size,
          requested: cidrs.size
      end
    end
  end
end

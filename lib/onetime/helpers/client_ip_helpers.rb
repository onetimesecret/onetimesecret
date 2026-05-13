# lib/onetime/helpers/client_ip_helpers.rb
#
# frozen_string_literal: true

require 'ipaddr'

module Onetime
  # Site-wide trusted-proxy-aware client IP resolution.
  #
  # All request.ip / req.ip callers should use trusted_client_ip (via the
  # RackExtension mixin) so that deployments behind Kubernetes ingress or
  # other RFC-1918 proxy chains return the real visitor IP instead of the
  # ingress pod address.
  #
  # Configuration (etc/defaults/config.defaults.yaml):
  #   site.trusted_proxy_depth  — 0 disables header trust (default, safe)
  #   site.trusted_ip_header    — 'X-Forwarded-For' | 'Forwarded' | 'Both'
  #
  module ClientIpHelpers
    # Extract the client IP from a Rack env hash.
    #
    # @param env    [Hash]    Rack environment
    # @param depth  [Integer] Number of trusted proxies to skip (0 = no trust)
    # @param header [String]  Which header to read ('X-Forwarded-For' | 'Forwarded' | 'Both')
    # @return [String, nil]   Client IP address
    def self.extract(env, depth:, header:)
      return env['REMOTE_ADDR'] if depth.nil? || depth <= 0

      forwarded = extract_forwarded_ips(env, header)
      return env['REMOTE_ADDR'] unless forwarded && !forwarded.empty?

      ip = if forwarded.length > depth
        forwarded[0...-depth].last
      else
        forwarded.first
      end

      ip || env['REMOTE_ADDR']
    end

    # Parse forwarded IPs from the appropriate request header.
    #
    # @param env         [Hash]   Rack environment
    # @param header_type [String] 'X-Forwarded-For', 'Forwarded', or 'Both'
    # @return [Array<String>, nil]
    def self.extract_forwarded_ips(env, header_type)
      case header_type
      when 'X-Forwarded-For'
        extract_x_forwarded_for(env)
      when 'Forwarded'
        extract_rfc7239_forwarded(env)
      when 'Both'
        extract_rfc7239_forwarded(env) || extract_x_forwarded_for(env)
      else
        extract_x_forwarded_for(env)
      end
    end

    # @param env [Hash] Rack environment
    # @return [Array<String>, nil]
    def self.extract_x_forwarded_for(env)
      val = env['HTTP_X_FORWARDED_FOR']
      return nil if val.nil? || val.empty?

      val.split(',').map(&:strip).reject(&:empty?)
    end

    # @param env [Hash] Rack environment
    # @return [Array<String>, nil]
    def self.extract_rfc7239_forwarded(env)
      val = env['HTTP_FORWARDED']
      return nil if val.nil? || val.empty?

      ips = []
      val.split(',').each do |segment|
        segment.split(';').each do |param|
          next unless param.strip =~ /^for=(.+)$/i

          ip = ::Regexp.last_match(1).gsub(/^["']|["']$/, '').gsub(/^\[|\]$/, '')
          ips << ip unless ip.empty?
        end
      end

      ips.empty? ? nil : ips
    end

    # Read site-level trusted_proxy_depth from OT config (integer, default 0).
    def self.site_depth
      OT.conf&.dig('site', 'trusted_proxy_depth').to_i
    end

    # Read site-level trusted_ip_header from OT config (string, default 'X-Forwarded-For').
    def self.site_header
      OT.conf&.dig('site', 'trusted_ip_header') || 'X-Forwarded-For'
    end

    # Mixin for Rack::Request — adds #trusted_client_ip.
    #
    # Included into Rack::Request at load time so it is available in all
    # contexts: Otto controllers, Rodauth hooks, middleware, and any code
    # that holds a Rack::Request instance.
    #
    module RackExtension
      def trusted_client_ip
        Onetime::ClientIpHelpers.extract(
          env,
          depth: Onetime::ClientIpHelpers.site_depth,
          header: Onetime::ClientIpHelpers.site_header,
        )
      end
    end
  end
end

# Apply RackExtension to Rack::Request at load time so trusted_client_ip is
# available in all contexts: Otto controllers, Rodauth hooks, and middleware.
Rack::Request.include(Onetime::ClientIpHelpers::RackExtension)

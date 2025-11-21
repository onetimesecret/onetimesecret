# frozen_string_literal: true

require 'ipaddr'

module Onetime
  module Helpers
    # Homepage Mode Detection
    #
    # Determines which homepage experience to show based on CIDR matching
    # and request header fallback. This module provides IP-based detection
    # with privacy-preserving CIDR validation.
    #
    # Usage:
    #   include Onetime::Helpers::HomepageModeHelpers
    #   mode = determine_homepage_mode(req, config)
    #
    module HomepageModeHelpers
      # Determines the homepage mode based on CIDR matching and header fallback
      #
      # Detection Priority:
      # 1. CIDR matching (client IP against configured ranges)
      # 2. Request header fallback (O-Homepage-Mode)
      #
      # Modes:
      # - 'internal': Normal homepage with full functionality
      # - 'external': Restricted view without secret creation
      # - nil: Default homepage behavior
      #
      # SECURITY:
      # - CIDR matching cannot be spoofed (primary method)
      # - Header only works as fallback (cannot override CIDR)
      # - This affects UI only, not authentication or API routes
      # - Privacy enforced: minimum /24 for IPv4, /48 for IPv6
      #
      # @param req [Rack::Request] The request object
      # @return [String, nil] 'internal', 'external', or nil
      def determine_homepage_mode
        ui_config = OT.conf.dig('site', 'interface', 'ui') || {}
        homepage_config = ui_config['homepage'] || {}

        configured_mode = homepage_config['mode']
        return nil unless %w[internal external].include?(configured_mode)

        OT.ld '[homepage_mode] Detection initiated', {
          mode: configured_mode,
        }

        # Initialize CIDR matchers (cached at instance level for efficiency)
        @cidr_matchers ||= compile_homepage_cidrs(homepage_config)

        # Extract client IP
        client_ip = extract_client_ip_for_homepage(homepage_config)
        mode_header_name = homepage_config['mode_header']

        # Priority 1: Check CIDR match
        if client_ip && ip_matches_homepage_cidrs?(client_ip)
          OT.ld '[homepage_mode] CIDR match', {
            mode: configured_mode,
            method: 'cidr',
          }
          return configured_mode
        end

        # Priority 2: Fallback to header check
        if mode_header_name && header_matches_mode?(mode_header_name, configured_mode)
          OT.ld '[homepage_mode] Header match', {
            mode: configured_mode,
            method: 'header',
          }
          return configured_mode
        end

        # No match - use default homepage
        OT.ld '[homepage_mode] No match - default homepage', {
          configured_mode: configured_mode,
        }
        nil
      end

      private

      # Compile CIDR ranges with privacy validation
      #
      # @param config [Hash] Homepage configuration
      # @return [Array<IPAddr>] Compiled CIDR blocks
      def compile_homepage_cidrs(config)
        cidrs = config['matching_cidrs'] || []
        return [] if cidrs.empty?

        cidrs.map do |cidr_string|
          cidr = IPAddr.new(cidr_string)

          # Validate privacy requirements
          unless validate_cidr_privacy(cidr)
            OT.info '[homepage_mode] CIDR rejected for privacy', {
              cidr: cidr_string,
              prefix: cidr.prefix,
            }
            next nil
          end

          cidr
        rescue IPAddr::InvalidAddressError => e
          OT.le '[homepage_mode] Invalid CIDR', {
            cidr: cidr_string,
            error: e.message,
          }
          nil
        end.compact
      end

      # Validate CIDR meets privacy requirements
      #
      # @param cidr [IPAddr] CIDR block to validate
      # @return [Boolean] True if CIDR meets privacy requirements
      def validate_cidr_privacy(cidr)
        min_prefix = cidr.ipv4? ? 24 : 48
        cidr.prefix >= min_prefix
      end

      # Extract client IP address from request
      #
      # Priority:
      # 1. Forwarded header (RFC 7239) or X-Forwarded-For (configurable)
      # 2. REMOTE_ADDR
      #
      # Security: When trusted_proxy_depth is 0, headers are IGNORED
      # to prevent IP spoofing. Only use trusted_proxy_depth > 0 when:
      # - Application is behind a trusted reverse proxy
      # - Direct access to application is blocked by firewall
      # - Proxy is configured to strip/override client-provided headers
      #
      # @param config [Hash] Homepage configuration
      # @return [String, nil] Client IP address or nil
      def extract_client_ip_for_homepage(config)
        trusted_proxy_depth = config['trusted_proxy_depth'] || 1
        trusted_ip_header   = config['trusted_ip_header'] || 'X-Forwarded-For'

        # Only trust forwarding headers if explicitly configured
        if trusted_proxy_depth > 0
          forwarded_ips = extract_forwarded_ips(trusted_ip_header)

          if forwarded_ips && !forwarded_ips.empty?
            # Remove the last N trusted proxy IPs, take the rightmost remaining IP
            if forwarded_ips.length > trusted_proxy_depth
              client_ips = forwarded_ips[0...-trusted_proxy_depth]
              ip = client_ips.last
            else
              # Edge case: fewer IPs than expected proxies, use first
              ip = forwarded_ips.first
            end

            OT.ld '[homepage_mode] Using forwarded header', {
              header_type: trusted_ip_header,
              forwarded_chain: forwarded_ips.join(', '),
              trusted_depth: trusted_proxy_depth,
              extracted_ip: ip,
            }
            return ip
          end
        end

        # Default to REMOTE_ADDR (most secure, cannot be spoofed)
        ip = req.env['REMOTE_ADDR']
        OT.ld '[homepage_mode] Using REMOTE_ADDR', {
          ip: ip,
        }
        ip
      end

      # Extract forwarded IPs from configured header type
      #
      # Supports X-Forwarded-For, Forwarded (RFC 7239), or Both
      #
      # @param header_type [String] 'X-Forwarded-For', 'Forwarded', or 'Both'
      # @return [Array<String>, nil] Array of IP addresses or nil
      def extract_forwarded_ips(header_type)
        case header_type
        when 'X-Forwarded-For'
          extract_x_forwarded_for
        when 'Forwarded'
          extract_rfc7239_forwarded
        when 'Both'
          # Try Forwarded first (RFC standard), fallback to X-Forwarded-For
          extract_rfc7239_forwarded || extract_x_forwarded_for
        else
          OT.info '[homepage_mode] Unknown trusted_ip_header type, using X-Forwarded-For', {
            configured_type: header_type,
          }
          extract_x_forwarded_for
        end
      end

      # Extract IPs from X-Forwarded-For header
      #
      # Format: X-Forwarded-For: client_ip, proxy1_ip, proxy2_ip
      #
      # @return [Array<String>, nil] Array of IP addresses or nil
      def extract_x_forwarded_for
        header_value = req.env['HTTP_X_FORWARDED_FOR']
        return nil if header_value.nil? || header_value.empty?

        header_value.split(',').map(&:strip)
      end

      # Extract IPs from RFC 7239 Forwarded header
      #
      # Format: Forwarded: for=client_ip, for=proxy1_ip;by=proxy2_ip
      #
      # @return [Array<String>, nil] Array of IP addresses or nil
      def extract_rfc7239_forwarded
        header_value = req.env['HTTP_FORWARDED']
        return nil if header_value.nil? || header_value.empty?

        # Parse RFC 7239 Forwarded header
        ips = []
        header_value.split(',').each do |segment|
          segment.split(';').each do |param|
            next unless param.strip =~ /^for=(.+)$/i

            ip = ::Regexp.last_match(1)
            # Remove quotes and IPv6 brackets if present
            ip = ip.gsub(/^["']|["']$/, '').gsub(/^\[|\]$/, '')
            ips << ip
          end
        end

        ips.empty? ? nil : ips
      end

      # Check if IP address matches any configured CIDR
      #
      # @param ip_string [String] IP address to check
      # @return [Boolean] True if IP is in configured ranges
      def ip_matches_homepage_cidrs?(ip_string)
        return false if ip_string.to_s.empty?
        return false if @cidr_matchers.empty?

        begin
          ip = IPAddr.new(ip_string)
          @cidr_matchers.any? { |cidr| cidr.include?(ip) }
        rescue IPAddr::InvalidAddressError => e
          OT.le '[homepage_mode] Invalid IP address', {
            ip: ip_string,
            error: e.message,
          }
          false
        end
      end

      # Check if request header matches expected mode value
      #
      # @param header_name [String] The header name to check (e.g., 'O-Homepage-Mode')
      # @param expected_mode [String] The mode to match against ('internal' or 'external')
      # @return [Boolean] True if header value matches expected mode
      def header_matches_mode?(header_name, expected_mode)
        return false if header_name.nil? || header_name.empty?

        # Normalize header name to HTTP_* format for env lookup
        # Convert dashes to underscores and prepend HTTP_ if not present
        header_key = header_name.upcase.tr('-', '_')
        header_key = "HTTP_#{header_key}" unless header_key.start_with?('HTTP_')

        header_value = req.env[header_key]
        return false if header_value.nil? || header_value.empty?

        # Check for exact match with expected mode
        header_value == expected_mode
      end
    end
  end
end

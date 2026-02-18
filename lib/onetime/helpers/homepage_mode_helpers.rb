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
      # 3. Default mode (if configured and no match found)
      #
      # Modes:
      # - 'internal': Normal homepage with full functionality
      # - 'external': Restricted view without secret creation
      # - nil: Default homepage behavior
      #
      # Configuration:
      # - mode: The mode to apply when IP matches CIDR ('internal' or 'external')
      # - matching_cidrs: Array of CIDR ranges to match against
      # - mode_header: Optional header name for fallback detection
      # - default_mode: Optional mode to apply when no match found
      #
      # SECURITY:
      # - CIDR matching cannot be spoofed (primary method)
      # - Header only works as fallback (cannot override CIDR)
      # - This affects UI only, not authentication or API routes
      # - Privacy enforced: minimum /24 for IPv4, /48 for IPv6
      #
      # @note This method expects `req` to be available in the including context
      #       (e.g., controller instance variable from Core::Controllers::Base)
      # @return [String, nil] 'internal', 'external', or nil
      def determine_homepage_mode
        ui_config = OT.conf.dig(:site, :interface, :ui) || {}
        homepage_config = ui_config[:homepage] || {}

        configured_mode = homepage_config[:mode]
        return nil unless %w[internal external].include?(configured_mode)

        # Memoized per controller instance (i.e. per request); no cross-request benefit.
        # Effectively compiled once since this method is only called once per request.
        @cidr_matchers ||= compile_homepage_cidrs(homepage_config)

        # Extract client IP
        client_ip = extract_client_ip_for_homepage(homepage_config)
        mode_header_name = homepage_config[:mode_header]
        default_mode = homepage_config[:default_mode]

        OT.ld '[homepage_mode] Detection started', {
          configured_mode: configured_mode,
          client_ip: client_ip,
          cidr_count: @cidr_matchers.length,
          header_configured: !mode_header_name.nil?,
          default_mode: default_mode,
        }

        # Priority 1: Check CIDR match
        if client_ip && ip_matches_homepage_cidrs?(client_ip)
          OT.ld '[homepage_mode] CIDR matched', {
            client_ip: client_ip,
            cidr_count: @cidr_matchers.length,
          }
          OT.info '[homepage_mode] Mode applied via CIDR', {
            mode: configured_mode,
            method: 'cidr',
            client_ip: client_ip,
          }
          return configured_mode
        end

        # Priority 2: Fallback to header check
        if mode_header_name && header_matches_mode?(mode_header_name, configured_mode)
          header_value = req.env["HTTP_#{mode_header_name.upcase.tr('-', '_')}"]
          OT.ld '[homepage_mode] Header matched', {
            header: mode_header_name,
            value: header_value,
          }
          OT.info '[homepage_mode] Mode applied via header', {
            mode: configured_mode,
            method: 'header',
            header: mode_header_name,
          }
          return configured_mode
        end

        # Priority 3: Use default_mode if configured
        if default_mode && %w[internal external].include?(default_mode)
          OT.ld '[homepage_mode] Using default_mode', {
            client_ip: client_ip,
            cidr_count: @cidr_matchers.length,
            header_configured: !mode_header_name.nil?,
            default_mode: default_mode,
          }
          OT.info '[homepage_mode] Mode applied via default_mode', {
            mode: default_mode,
            method: 'default',
          }
          return default_mode
        end

        # No match - use default homepage
        OT.ld '[homepage_mode] No match found', {
          client_ip: client_ip,
          cidr_count: @cidr_matchers.length,
          header_configured: !mode_header_name.nil?,
          default_mode: default_mode,
        }
        OT.info '[homepage_mode] No mode applied (default homepage)', {
          mode: nil,
          method: 'none',
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
        cidrs = config[:matching_cidrs] || []
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
      # Privacy Logic: Smaller prefix numbers = broader ranges = MORE private
      # - IPv4 /8 covers 16M IPs (very broad, very private)
      # - IPv4 /24 covers 254 IPs (minimum acceptable breadth)
      # - IPv4 /32 is a single host (no privacy, rejected)
      #
      # We enforce a MAXIMUM prefix to ensure sufficient breadth:
      # - Accept /1 through /24 for IPv4 (broad ranges)
      # - Reject /25 through /32 for IPv4 (too narrow to preserve privacy)
      #
      # @param cidr [IPAddr] CIDR block to validate
      # @return [Boolean] True if CIDR meets privacy requirements
      def validate_cidr_privacy(cidr)
        max_prefix = cidr.ipv4? ? 24 : 48
        cidr.prefix <= max_prefix
      end

      # Extract client IP address from request
      #
      # Logical Flow:
      # 1. Try to extract from trusted headers (if behind proxy)
      # 2. Validate extracted IP is not a private proxy IP
      # 3. Fall back to REMOTE_ADDR (most secure, cannot be spoofed)
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
        trusted_proxy_depth = config[:trusted_proxy_depth] || 1
        trusted_ip_header   = config[:trusted_ip_header] || 'X-Forwarded-For'
        remote_addr = req.env['REMOTE_ADDR']
        ip = nil

        OT.ld '[homepage_mode] IP extraction config', {
          trusted_proxy_depth: trusted_proxy_depth,
          trusted_ip_header: trusted_ip_header,
          remote_addr: remote_addr,
        }

        # Step 1: Try to extract from trusted headers (if behind proxy)
        if trusted_proxy_depth > 0
          ip = extract_ip_from_header(trusted_ip_header, trusted_proxy_depth)
          if ip
            OT.ld '[homepage_mode] Extracted from header', {
              header_type: trusted_ip_header,
              extracted_ip: ip,
            }
          end
        else
          OT.ld '[homepage_mode] Skipping header extraction (trusted_proxy_depth=0)'
        end

        # Step 2: Validate extracted IP is not a private proxy IP
        # This prevents spoofed private IPs in headers from being used
        if ip && private_ip?(ip)
          OT.ld '[homepage_mode] Rejected private IP from header', {
            extracted_ip: ip,
            reason: 'private_ip_validation_failed',
          }
          ip = nil
        end

        # Step 3: Use extracted IP or fall back to REMOTE_ADDR
        final_ip = ip || remote_addr
        OT.ld '[homepage_mode] Final IP selected', {
          ip: final_ip,
          source: ip ? 'header' : 'remote_addr',
        }
        final_ip
      end

      # Extract IP from forwarded header with proxy depth handling
      #
      # @param header_type [String] Header type to extract from
      # @param trusted_proxy_depth [Integer] Number of trusted proxies to skip
      # @return [String, nil] Extracted IP address or nil
      def extract_ip_from_header(header_type, trusted_proxy_depth)
        forwarded_ips = extract_forwarded_ips(header_type)
        return nil if forwarded_ips.nil? || forwarded_ips.empty?

        OT.ld '[homepage_mode] Processing forwarded IPs', {
          header_type: header_type,
          forwarded_chain: forwarded_ips.join(', '),
          chain_length: forwarded_ips.length,
          trusted_proxy_depth: trusted_proxy_depth,
        }

        # Remove the last N trusted proxy IPs, take the rightmost remaining IP
        if forwarded_ips.length > trusted_proxy_depth
          client_ips = forwarded_ips[0...-trusted_proxy_depth]
          extracted_ip = client_ips.last
          OT.ld '[homepage_mode] Extracted client IP from chain', {
            client_ips: client_ips.join(', '),
            selected_ip: extracted_ip,
          }
          extracted_ip
        else
          # Edge case: fewer IPs than expected proxies, use first
          extracted_ip = forwarded_ips.first
          OT.ld '[homepage_mode] Chain shorter than proxy depth, using first IP', {
            forwarded_ips: forwarded_ips.join(', '),
            selected_ip: extracted_ip,
          }
          extracted_ip
        end
      end

      # Check if IP address is in private/reserved ranges
      #
      # Prevents spoofed private IPs in X-Forwarded-For headers from
      # being used for homepage mode detection. Private IPs should only
      # come from REMOTE_ADDR (the actual connection), not from headers
      # which can be manipulated.
      #
      # @param ip_string [String] IP address to check
      # @return [Boolean] True if IP is private/reserved
      def private_ip?(ip_string)
        return true if ip_string.nil? || ip_string.empty?

        begin
          ip = IPAddr.new(ip_string)

          # RFC 1918 private IPv4 ranges + special use ranges
          private_ranges = [
            IPAddr.new('10.0.0.0/8'),       # RFC 1918 private
            IPAddr.new('172.16.0.0/12'),    # RFC 1918 private
            IPAddr.new('192.168.0.0/16'),   # RFC 1918 private
            IPAddr.new('127.0.0.0/8'),      # Loopback
            IPAddr.new('169.254.0.0/16'),   # Link-local
            IPAddr.new('::1/128'),          # IPv6 loopback
            IPAddr.new('fc00::/7'),         # IPv6 unique local
            IPAddr.new('fe80::/10'),        # IPv6 link-local
          ]

          private_ranges.any? { |range| range.include?(ip) }
        rescue IPAddr::InvalidAddressError
          true # Treat invalid IPs as private (safe default)
        end
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

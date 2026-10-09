# lib/onetime/helpers/homepage_mode_helpers.rb
#
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
      # - CIDR matching is judged at full /32-/128 precision through
      #   env['otto.ip_match'] without the unmasked IP reaching this code
      #   (see #homepage_cidrs_match?)
      #
      # @param req [Rack::Request] The request object
      # @return [String, nil] 'internal', 'external', or nil
      def determine_homepage_mode
        ui_config       = OT.conf.dig('site', 'interface', 'ui') || {}
        homepage_config = ui_config['homepage'] || {}

        configured_mode = homepage_config['mode']
        return nil unless %w[internal external].include?(configured_mode)

        # Initialize CIDR matchers (cached at instance level for efficiency)
        @cidr_matchers ||= compile_homepage_cidrs(homepage_config)

        # Extract client IP
        client_ip        = extract_client_ip_for_homepage
        mode_header_name = homepage_config['mode_header']

        # Priority 1: Check CIDR match
        if homepage_cidrs_match?(client_ip)
          http_logger.debug '[homepage_mode] Matched',
            {
              mode: configured_mode,
              method: 'cidr',
              ip: client_ip,
            }
          return configured_mode
        end

        # Priority 2: Fallback to header check
        if mode_header_name && header_matches_mode?(mode_header_name, configured_mode)
          http_logger.debug '[homepage_mode] Matched',
            {
              mode: configured_mode,
              method: 'header',
              header: mode_header_name,
            }
          return configured_mode
        end

        # No match - use default homepage
        http_logger.debug '[homepage_mode] No match',
          {
            mode: configured_mode,
            client_ip: client_ip,
            cidr_count: @cidr_matchers.length,
            header_configured: !mode_header_name.nil?,
          }
        nil
      end

      private

      # Compile CIDR ranges
      #
      # Every entry that parses is kept, at any prefix length. Entries finer
      # than /24 (IPv4) or /48 (IPv6) are only ever judged through
      # env['otto.ip_match']; the no-closure fallback skips them (see
      # #ip_matches_homepage_cidrs?). Entries that do not parse are dropped
      # with an error log, as before.
      #
      # @param config [Hash] Homepage configuration
      # @return [Array<IPAddr>] Compiled CIDR blocks
      def compile_homepage_cidrs(config)
        cidrs = config['matching_cidrs'] || []
        return [] if cidrs.empty?

        cidrs.map do |cidr_string|
          IPAddr.new(cidr_string)
        rescue IPAddr::InvalidAddressError => ex
          http_logger.error '[homepage_mode] Invalid CIDR',
            {
              cidr: cidr_string,
              error: ex.message,
            }
          nil
        end.compact
      end

      # Whether a CIDR is coarse enough to judge against a privacy-masked IP
      #
      # The universal IPPrivacyMiddleware mount zeroes the last IPv4 octet
      # (IPv6: the last 80 bits), so a masked address still lands in the right
      # /24 (/48) but says nothing finer. Accepts ranges where the prefix
      # number is at or below that mask.
      # Remember: Lower prefix = broader network
      #   /17 = 32,766 IPs (BROAD) ✓
      #   /24 = 254 IPs (threshold)
      #   /32 = 1 IP (NARROW, finer than the mask) ✗
      #
      # Only the no-closure fallback uses this. Through env['otto.ip_match']
      # every prefix length is judged at full precision.
      #
      # @param cidr [IPAddr] CIDR block to check
      # @return [Boolean] True if the prefix is at or below the mask
      def validate_cidr_privacy(cidr)
        max_prefix = cidr.ipv4? ? 24 : 48  # Maximum prefix value (minimum network size)
        cidr.prefix <= max_prefix           # Accept if prefix number is at or below threshold
      end

      # Returns the client IP used for homepage CIDR matching.
      #
      # Delegates to Otto::Request#ip, which reads the canonical
      # env['otto.client_ip'] resolved once by the universal IPPrivacyMiddleware
      # mount (configured from site.network.trusted_proxy via
      # MiddlewareStack.ip_privacy_security_config). Homepage mode carries no
      # proxy config of its own, so CIDR matching stays consistent with every
      # other IP-based feature.
      #
      # @return [String, nil] Client IP address
      def extract_client_ip_for_homepage
        req.ip
      end

      # Membership in the configured ranges at full precision when the
      # request came through the otto mount, at the resolved value otherwise.
      #
      # env['otto.ip_match'] is the verdict-only closure IPPrivacyMiddleware
      # installs over the resolved PRE-MASK client IP. It is consulted first
      # because req.ip is already privacy-masked here, and a masked address
      # misjudges any range finer than the mask. @cidr_matchers is handed
      # over as the pre-parsed IPAddr list, so a malformed configured entry
      # (dropped at compile) cannot make the closure raise. The closure
      # answers false when the request had no resolvable IP. Same pattern as
      # AdminNetworkIsolation#network_allowed?.
      #
      # A request that never passed IPPrivacyMiddleware carries no closure;
      # anything non-callable in the key is judged the same way, never
      # called. #ip_matches_homepage_cidrs? then compares the resolved IP
      # with the /24 (/48) floor that held before the closure existed, since
      # that path cannot tell a masked IP from a real one.
      #
      # Any error is no match. The log carries the error class only: an
      # address-parse message can contain the address.
      #
      # @param client_ip [String, nil] req.ip, used only by the fallback
      # @return [Boolean] True if the client is in configured ranges
      def homepage_cidrs_match?(client_ip)
        return false if @cidr_matchers.empty?

        matcher = req.env['otto.ip_match']
        return ip_matches_homepage_cidrs?(client_ip) unless matcher.respond_to?(:call)

        matcher.call(@cidr_matchers) == true
      rescue StandardError => ex
        http_logger.warn '[homepage_mode] CIDR match failed; treating as no match',
          {
            error: ex.class.name,
          }
        false
      end

      # Check if IP address matches any configured CIDR coarse enough to
      # judge against a masked IP (the no-closure fallback)
      #
      # @param ip_string [String] IP address to check
      # @return [Boolean] True if IP is in configured ranges
      def ip_matches_homepage_cidrs?(ip_string)
        return false if ip_string.to_s.empty?
        return false if @cidr_matchers.empty?

        begin
          ip = IPAddr.new(ip_string)
          @cidr_matchers.any? { |cidr| validate_cidr_privacy(cidr) && cidr.include?(ip) }
        rescue IPAddr::InvalidAddressError => ex
          http_logger.error '[homepage_mode] Invalid IP address',
            {
              ip: ip_string,
              error: ex.message,
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

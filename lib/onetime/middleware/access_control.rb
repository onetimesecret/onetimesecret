# lib/onetime/middleware/access_control.rb
#
# frozen_string_literal: true

require 'ipaddr'
require_relative '../../middleware/logging'

module Onetime
  module Middleware
    # AccessControl Middleware
    #
    # Signals access mode based on IP allowlist matching. NEVER blocks requests.
    # Sets downstream header for application consumption.
    #
    # ## Logic Flow
    #
    # 1. If not enabled → passthrough (no header)
    # 2. If trigger header absent → passthrough (no header)
    # 3. If trigger header present but secret mismatch → passthrough (no header)
    # 4. If trigger header + secret match → check IP:
    #    - IP in allowed_cidrs → set mode header to 'allow' value
    #    - IP not in allowed_cidrs → set mode header to 'deny' value
    #
    # ## Configuration
    #
    # ```yaml
    # access_control:
    #   enabled: true
    #   trigger:
    #     header: 'O-Access-Control-Trigger'
    #     secret: 'shared-secret-with-proxy'
    #   allowed_cidrs:
    #     - '10.0.0.0/8'
    #     - '172.16.0.0/12'
    #   mode:
    #     header: 'O-Access-Mode'
    #     allow: 'normal'
    #     deny: 'protected'
    #   trusted_proxy_depth: 1  # Number of trusted proxies in chain
    # ```
    #
    # ## Usage
    #
    # In middleware stack (before IPPrivacyMiddleware):
    #
    # ```ruby
    # use Onetime::Middleware::AccessControl, config[:access_control]
    # ```
    #
    # In application code:
    #
    # ```ruby
    # def index(req, res)
    #   if req.env['HTTP_O_ACCESS_MODE'] == 'protected'
    #     # Show "Internal Use Only" page
    #   else
    #     # Show normal homepage
    #   end
    # end
    # ```
    #
    # ## Security Model
    #
    # - Trigger secret prevents spoofing by clients
    # - Only trusted infrastructure (reverse proxy, load balancer) knows secret
    # - Separation of concerns: middleware signals, application enforces
    # - Runs before IPPrivacyMiddleware to access original IPs
    #
    # ⚠️  CRITICAL: X-Forwarded-For Security
    #
    # By default (trusted_proxy_depth: 0), X-Forwarded-For is IGNORED to prevent
    # IP spoofing attacks. Only set trusted_proxy_depth > 0 when ALL these conditions are met:
    #
    # 1. Application is behind a trusted reverse proxy
    # 2. Direct access to application is BLOCKED by firewall
    # 3. Proxy strips/overrides any client-provided X-Forwarded-For headers
    #
    # Example attack without firewall protection:
    #   curl -H "X-Forwarded-For: 10.0.0.1" http://app:3000/
    #   # Attacker spoofs internal IP, bypassing allowlist
    #
    # Safe configuration requires both:
    # - trusted_proxy_depth matching your proxy chain length
    # - Firewall rules blocking direct access to application
    #
    class AccessControl
      include ::Middleware::Logging

      def initialize(app, config = {}, logger: nil)
        @app           = app
        @config        = normalize_config(config)
        @custom_logger = logger

        # Pre-compile CIDR blocks for performance
        @allowed_cidrs = compile_cidrs(@config[:allowed_cidrs])

        # Validate configuration
        validate_config!
      end

      # Override logger to allow custom logger injection
      def logger
        @custom_logger || super
      end

      def call(env)
        # Short-circuit if disabled
        unless @config[:enabled]
          logger.debug('[AccessControl] Disabled, passthrough')
          return @app.call(env)
        end

        # Check for trigger header activation
        trigger_header_key = header_to_rack_key(@config[:trigger][:header])
        trigger_value = env[trigger_header_key]

        # Passthrough if trigger header absent
        unless trigger_value
          logger.debug('[AccessControl] No trigger header, passthrough')
          return @app.call(env)
        end

        # Passthrough if secret mismatch (ignore malformed triggers)
        unless secure_compare(trigger_value, @config[:trigger][:secret])
          logger.warn('[AccessControl] Trigger secret mismatch, passthrough')
          return @app.call(env)
        end

        # Trigger activated - evaluate IP
        logger.debug('[AccessControl] Trigger activated, evaluating IP')
        client_ip = extract_client_ip(env)

        unless client_ip
          logger.warn('[AccessControl] Cannot determine client IP, defaulting to deny mode')
          set_mode_header(env, :deny)
          return @app.call(env)
        end

        # Check if IP is in allowlist
        if ip_allowed?(client_ip)
          logger.info("[AccessControl] IP #{client_ip} allowed (matches CIDR)")
          set_mode_header(env, :allow)
        else
          logger.info("[AccessControl] IP #{client_ip} denied (no CIDR match)")
          set_mode_header(env, :deny)
        end

        # Always passthrough - application decides what to do with mode
        @app.call(env)
      end

      private

      # Normalize and set defaults for configuration
      #
      # @param config [Hash] Raw configuration
      # @return [Hash] Normalized configuration
      def normalize_config(config)
        config ||= {}

        {
          enabled: config[:enabled] || false,
          trigger: {
            header: config.dig(:trigger, :header) || 'O-Access-Control-Trigger',
            secret: config.dig(:trigger, :secret) || '',
          },
          allowed_cidrs: Array(config[:allowed_cidrs]).compact,
          mode: {
            header: config.dig(:mode, :header) || 'O-Access-Mode',
            allow: config.dig(:mode, :allow) || 'normal',
            deny: config.dig(:mode, :deny) || 'protected',
          },
          trusted_proxy_depth: config[:trusted_proxy_depth].nil? ? 0 : config[:trusted_proxy_depth].to_i,
        }
      end

      # Validate configuration at initialization
      #
      # @raise [ArgumentError] if configuration is invalid
      def validate_config!
        if @config[:enabled]
          if @config[:trigger][:secret].to_s.empty?
            raise ArgumentError, 'AccessControl: trigger.secret must be set when enabled'
          end

          if @config[:allowed_cidrs].empty?
            logger.warn('[AccessControl] No allowed_cidrs configured - all IPs will be denied')
          end
        end
      end

      # Pre-compile CIDR blocks into IPAddr objects
      #
      # @param cidrs [Array<String>] CIDR notation strings
      # @return [Array<IPAddr>] Compiled CIDR blocks
      def compile_cidrs(cidrs)
        cidrs.map do |cidr_string|
          IPAddr.new(cidr_string)
        rescue IPAddr::InvalidAddressError => e
          logger.error("[AccessControl] Invalid CIDR '#{cidr_string}': #{e.message}")
          nil
        end.compact
      end

      # Extract client IP address from request
      #
      # Priority:
      # 1. X-Forwarded-For (with trusted proxy depth consideration)
      # 2. REMOTE_ADDR
      #
      # Security: When trusted_proxy_depth is 0 (default), X-Forwarded-For is
      # IGNORED to prevent IP spoofing. Only use trusted_proxy_depth > 0 when:
      # - Application is behind a trusted reverse proxy
      # - Direct access to application is blocked by firewall
      # - Proxy is configured to strip/override client-provided X-Forwarded-For
      #
      # @param env [Hash] Rack environment
      # @return [String, nil] Client IP address or nil
      def extract_client_ip(env)
        # Only trust X-Forwarded-For if explicitly configured
        if @config[:trusted_proxy_depth] > 0 && env['HTTP_X_FORWARDED_FOR']
          forwarded_ips = env['HTTP_X_FORWARDED_FOR'].split(',').map(&:strip)

          # Take the rightmost IP that's outside our proxy chain
          # If trusted_proxy_depth = 1, take the last IP (closest to us)
          # If trusted_proxy_depth = 2, take second-to-last IP, etc.
          index = -(1 + @config[:trusted_proxy_depth])
          ip = forwarded_ips[index] || forwarded_ips.first

          logger.debug("[AccessControl] Using X-Forwarded-For[#{index}]: #{ip} (depth: #{@config[:trusted_proxy_depth]})")
          return ip
        end

        # Default: Use REMOTE_ADDR (most secure, can't be spoofed)
        ip = env['REMOTE_ADDR']
        logger.debug("[AccessControl] Using REMOTE_ADDR: #{ip}")
        ip
      end

      # Check if IP address matches any allowed CIDR block
      #
      # @param ip_string [String] IP address to check
      # @return [Boolean] true if IP is in allowlist
      def ip_allowed?(ip_string)
        return false if ip_string.to_s.empty?

        begin
          ip = IPAddr.new(ip_string)

          @allowed_cidrs.any? do |cidr|
            cidr.include?(ip)
          end
        rescue IPAddr::InvalidAddressError => e
          logger.error("[AccessControl] Invalid IP address '#{ip_string}': #{e.message}")
          false
        end
      end

      # Set mode header in environment
      #
      # @param env [Hash] Rack environment
      # @param mode [Symbol] :allow or :deny
      def set_mode_header(env, mode)
        mode_header_key = header_to_rack_key(@config[:mode][:header])
        mode_value = mode == :allow ? @config[:mode][:allow] : @config[:mode][:deny]

        env[mode_header_key] = mode_value
        logger.debug("[AccessControl] Set #{@config[:mode][:header]}: #{mode_value}")
      end

      # Convert HTTP header name to Rack env key
      #
      # @param header_name [String] HTTP header name (e.g., 'O-Access-Mode')
      # @return [String] Rack env key (e.g., 'HTTP_O_ACCESS_MODE')
      def header_to_rack_key(header_name)
        "HTTP_#{header_name.upcase.tr('-', '_')}"
      end

      # Constant-time string comparison to prevent timing attacks
      #
      # @param a [String] First string
      # @param b [String] Second string
      # @return [Boolean] true if strings match
      def secure_compare(a, b)
        return false if a.nil? || b.nil?
        return false unless a.bytesize == b.bytesize

        l = a.unpack('C*')
        r = b.unpack('C*')

        result = 0
        l.zip(r) { |x, y| result |= x ^ y }
        result.zero?
      end
    end
  end
end

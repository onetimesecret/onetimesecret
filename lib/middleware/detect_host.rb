# lib/middleware/detect_host.rb
#
# frozen_string_literal: true

require 'ipaddr'
require_relative 'logging'

module Rack
  # Middleware to accurately detect the client's host in a Rack application.
  #
  # This middleware examines incoming HTTP requests and attempts to determine
  # the correct host by inspecting a prioritized list of HTTP headers. While
  # Rack's default `req.host` method provides basic host detection using the
  # `Host` header, this middleware extends that functionality by considering
  # additional headers that are commonly set by proxies and load balancers.
  #
  # ### Rationale
  #
  # In environments where the application is behind reverse proxies, load
  # balancers, or CDN services (like AWS ALB, nginx, or CloudFlare), the
  # client-requested host may be forwarded via headers like
  # `X-Forwarded-Host` or `X-Original-Host`. Rack does not trust these
  # headers by default for security reasons, as they can be spoofed by
  # clients.
  #
  # However, in controlled environments where these proxy headers are set by
  # trusted infrastructure components, it's necessary to respect these headers
  # to accurately determine the host for proper URL generation, redirection,
  # and processing in multi-tenant applications.
  #
  # This middleware prioritizes host detection in the following order:
  #
  # 1. `X-Forwarded-Host` - Commonly used by proxies and load balancers.
  # 2. `X-Original-Host` - Used by various proxy services.
  # 3. `Forwarded` - The standard header as per RFC 7239.
  # 4. `Host` - Default HTTP host header.
  #
  # It also includes validation to filter out invalid or local hosts (e.g.,
  # `localhost`, `127.0.0.1`) and IP addresses, ensuring only legitimate
  # external hosts are considered.
  #
  # ### Configuration
  #
  # The middleware allows setting a class-level `result_field_name` variable,
  # which can be initialized from an environment variable `DETECTED_HOST`.
  #
  # ```ruby
  # Rack::DetectHost.result_field_name = ENV['DETECTED_HOST'] || 'default_host_value'
  # ```
  #
  # ### Usage
  #
  # Use this middleware in your Rack-based application by inserting it into
  # the middleware stack:
  #
  # ```ruby
  # use Rack::DetectHost
  # ```
  #
  # After the middleware processes a request, it sets `env['rack.detected_host']`
  # with the determined host value, which can be used downstream in your
  # application for routing or generating URLs.
  #
  # ### Security Considerations
  #
  # **Trusted Proxy Validation**: This middleware only trusts forwarded host
  # headers (X-Forwarded-Host, X-Original-Host, Apx-Incoming-Host, Forwarded)
  # when the request arrived via a trusted reverse proxy. Trust is granted
  # when EITHER of two independent signals says so:
  #
  # - env['otto.via_trusted_proxy'] is true — recorded by Otto's
  #   IPPrivacyMiddleware (mounted earlier in the stack) from the ORIGINAL
  #   connecting peer, before it rewrites REMOTE_ADDR to the resolved client
  #   IP. Otto grants it when the peer matches a configured trusted-proxy
  #   CIDR (filter mode) or whenever count-based depth mode is active
  #   (configuring a depth asserts the peer is the proxy tier; otto#226); or
  # - REMOTE_ADDR is a private/loopback address — the legacy heuristic that
  #   keeps self-hosted installs behind a local reverse proxy working when
  #   no trusted-proxy list is configured.
  #
  # A false (or missing, or non-boolean) key never suppresses the heuristic:
  # IPPrivacyMiddleware is mounted unconditionally and writes false on every
  # request when proxy trust is unconfigured, so false is ambiguous between
  # "untrusted peer" and "no proxy trust configured". Direct requests from
  # public IPs can only use the Host header.
  #
  # This prevents header spoofing attacks where malicious clients set
  # X-Forwarded-Host to impersonate different hosts.
  #
  # ### Note on Rack's Default Behavior
  #
  # While Rack's `request.host` method provides basic host detection using
  # the `Host` header, it does not, by default, consider proxy-related headers
  # like `X-Forwarded-Host` unless explicitly configured. This middleware
  # enhances host detection by considering these headers, which is essential
  # in proxy and load-balanced environments where the original host is forwarded
  # by trusted components.
  #
  class DetectHost
    include Middleware::Logging

    # NOTE: CF-Visitor header only contains scheme information { "scheme": "https" }
    # and is not used for host detection
    unless defined?(HEADER_PRECEDENCE)
      # Forwarded headers that require trusted proxy validation.
      # These headers can be spoofed by clients and should only be trusted
      # when the request comes from a private/loopback IP (trusted proxy).
      FORWARDED_HEADERS = [
        'X-Forwarded-Host',   # Common proxy header (AWS ALB, nginx)
        'Apx-Incoming-Host',  # Check Approximated (if it exists)
        'X-Original-Host',    # Various proxy services
        'Forwarded',          # RFC 7239 standard (host parameter)
      ].freeze

      # List of HTTP headers that might contain the host, in order of precedence.
      # Headers earlier in the list are given priority over later ones.
      # NOTE: FORWARDED_HEADERS are only checked when request comes from trusted proxy.
      HEADER_PRECEDENCE = (FORWARDED_HEADERS + ['Host']).freeze

      # Hostnames and IP addresses that should never be accepted as valid hosts.
      # These typically indicate local or development environments.
      INVALID_HOSTS = [
        'localhost',
        'localhost.localdomain',
        '127.0.0.1',
        '::1',
      ].freeze

      # Rack env key written by Otto's IPPrivacyMiddleware. Mirrors
      # Otto::EnvKeys::VIA_TRUSTED_PROXY — kept as a literal so this
      # middleware stays otto-agnostic (a tryout pins the equality).
      VIA_TRUSTED_PROXY_KEY = 'otto.via_trusted_proxy'
    end

    # Class-level setting initialized from ENV variable
    @result_field_name = ENV['DETECTED_HOST'] || 'rack.detected_host'

    class << self
      attr_accessor :result_field_name
    end

    # Initializes the middleware with the application and logging options.
    #
    # @param app [#call] The Rack application
    # @param logger [Logger, nil] Optional logger instance to use
    # @return [void]
    def initialize(app, logger: nil)
      @app           = app
      @custom_logger = logger
    end

    # Override logger to allow custom logger injection
    def logger
      @custom_logger || super
    end

    # Processes the request and determines the appropriate host.
    #
    # @param env [Hash] Rack environment hash
    # @return [Array] Standard Rack response array from the next middleware
    #
    # This method:
    # 1. Determines if request is from a trusted proxy (otto's trusted-proxy
    #    signal, or a private/loopback REMOTE_ADDR)
    # 2. Examines headers in order of precedence (forwarded headers only from trusted proxies)
    # 3. Normalizes and validates each potential host
    # 4. Accepts the first valid host found
    # 5. Stores the result in env[result_field_name]
    # 6. Passes the request to the next middleware
    def call(env)
      result_field_name = self.class.result_field_name
      detected_host     = nil

      # Determine which headers to check based on whether request comes from
      # a trusted proxy. Forwarded headers can be spoofed by clients, so they
      # are only honored for requests that arrived via trusted infrastructure.
      #
      # Trust is a deliberate OR of two independent signals — the otto key
      # can GRANT trust but never REVOKE the legacy heuristic:
      #
      # a. env['otto.via_trusted_proxy'] == true wins outright. Otto's
      #    IPPrivacyMiddleware (mounted earlier in the stack) records it from
      #    the ORIGINAL connecting peer against the configured trusted-proxy
      #    CIDRs, then rewrites REMOTE_ADDR to the resolved client IP. After
      #    that rewrite REMOTE_ADDR no longer identifies the peer — with
      #    proxy trust enabled it holds the real (public) visitor IP, so
      #    re-checking it here would wrongly discard forwarded host headers
      #    and fail every custom domain to canonical (2026-08-05 incident).
      # b. A false key does NOT suppress private_ip?(REMOTE_ADDR).
      #    IPPrivacyMiddleware is mounted unconditionally and writes false on
      #    every request when no trusted proxies are configured, so false is
      #    ambiguous between "untrusted peer" and "no proxy trust
      #    configured". Treating it as authoritative stripped forwarded-host
      #    trust from default-config self-hosters behind a local reverse
      #    proxy, whose masked REMOTE_ADDR stays private. Non-boolean values
      #    (nil, strings from a future otto) also fall through gracefully.
      # c. TRUSTED_PROXY_MODE=depth: fixed upstream in otto#226. Depth and
      #    CIDRs are mutually exclusive so otto's matcher list is empty, but
      #    configuring a depth is the operator's assertion that the
      #    connecting peer is their proxy tier, so otto records the key true
      #    and grant (a) applies. (Until the otto#151 depth remap is
      #    reconciled, depth mode remains spoofable in the documented
      #    single-proxy setup — operator docs steer to filter mode.)
      remote_addr        = env['REMOTE_ADDR']
      from_trusted_proxy = env[VIA_TRUSTED_PROXY_KEY] == true ||
                           self.class.private_ip?(remote_addr)

      headers_to_check = if from_trusted_proxy
        HEADER_PRECEDENCE
      else
        # Untrusted source: only the Host header is honored.
        log_untrusted_request(env, remote_addr)
        ['Host']
      end

      # Try headers in order of precedence
      headers_to_check.each do |header|
        header_key = "HTTP_#{header.tr('-', '_').upcase}"
        host       = self.class.normalize_host(env[header_key])
        next if host.nil?

        if self.class.valid_domain_name?(host)
          detected_host = host
          logger.debug("[DetectHost] #{host} via #{header_key}")
          break # stop on first valid host
        elsif self.class.private_ip?(host)
          logger.debug("[DetectHost] Private IP address #{host} via #{header_key}")
        elsif self.class.valid_ip?(host)
          logger.warn("[DetectHost] External IP address #{host} via #{header_key}")
        else
          logger.debug("[DetectHost] Invalid host detected #{host} via #{header_key}")
        end
      end

      # Log indication if no valid host found in debug mode
      unless detected_host
        logger.debug('[DetectHost] No valid host detected in request')
      end

      # e.g. env['rack.detected_host'] = 'example.com'
      env[result_field_name] = detected_host

      @app.call(env)
    end

    private

    # Logs why forwarded host headers are being ignored for this request,
    # stating the actual trust inputs (the otto key's presence/value and the
    # private_ip? result). REMOTE_ADDR is labeled post-proxy-resolution: by
    # the time this middleware runs, IPPrivacyMiddleware may have rewritten
    # it, so it does not necessarily identify the connecting peer.
    #
    # Escalates to WARN when Apx-Incoming-Host is among the discarded
    # headers: Approximated ingress always sends it and a legitimate direct
    # public client never does, so a discard here is the exact signature of
    # the 2026-08-05 incident (custom domains falling back to canonical).
    #
    # @param env [Hash] Rack environment hash
    # @param remote_addr [String, nil] env['REMOTE_ADDR'] after any rewrite
    # @return [void]
    def log_untrusted_request(env, remote_addr)
      via_key      = env.key?(VIA_TRUSTED_PROXY_KEY) ? env[VIA_TRUSTED_PROXY_KEY].inspect : 'absent'
      trust_inputs = "#{VIA_TRUSTED_PROXY_KEY}=#{via_key}, " \
                     "private_ip=#{self.class.private_ip?(remote_addr)}, " \
                     "remote_addr=#{remote_addr} (post-proxy-resolution)"

      discarded    = FORWARDED_HEADERS.select do |header|
        env.key?("HTTP_#{header.tr('-', '_').upcase}")
      end

      if discarded.empty?
        logger.debug("[DetectHost] Untrusted source, no forwarded host headers present (#{trust_inputs})")
      elsif discarded.include?('Apx-Incoming-Host')
        logger.warn(
          "[DetectHost] Discarding forwarded host headers (#{discarded.join(', ')}) " \
          'from untrusted source; Apx-Incoming-Host present — matches the 2026-08-05 ' \
          "Approximated-ingress incident signature (#{trust_inputs})",
        )
      else
        logger.debug(
          "[DetectHost] Discarding forwarded host headers (#{discarded.join(', ')}) " \
          "from untrusted source (#{trust_inputs})",
        )
      end
    end

    module ClassMethods
      # Extracts and normalizes the host from a header value.
      #
      # @param value_unsafe [String, nil] Raw header value from the request
      # @return [String, nil] Normalized host without port number, or nil if empty
      #
      # This method:
      # - Takes the first host if multiple are provided (comma-separated)
      # - Delegates to DomainParser for port stripping and normalization
      # - Returns nil for empty values
      def normalize_host(value_unsafe)
        # Handle comma-separated hosts (e.g., X-Forwarded-Host header)
        first_host = value_unsafe.to_s.split(',').first.to_s

        # Delegate core normalization to DomainParser
        Onetime::Utils::DomainParser.extract_hostname(first_host)
      end

      # Determines if a string is a valid host for use in this application.
      #
      # @param host [String] The host to validate
      # @return [Boolean] true if the host is a valid domain name
      #
      # Note: This method intentionally rejects IP addresses as we require
      # domain names for our application's routing logic.
      def valid_domain_name?(host)
        return false if INVALID_HOSTS.include?(host)
        return false if valid_ip?(host)

        true
      end

      # Determines if a string represents a private IP address.
      #
      # @param ip_string [String, nil] String to check
      # @return [Boolean] true if the string is a valid private IP address
      #
      # Checks for:
      # - IPv4 private ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
      # - IPv4 loopback addresses (127.0.0.0/8)
      # - IPv6 unique local addresses (fc00::/7)
      # - IPv6 link-local addresses (fe80::/10)
      # - IPv6 loopback address (::1/128)
      def private_ip?(ip_string)
        return false if ip_string.to_s.empty?

        ip = IPAddr.new(ip_string)

        # Check for private IPv4 ranges (RFC 1918)
        if ip.ipv4?
          return ip.private? || ip.loopback?

        # Check for private IPv6 ranges
        elsif ip.ipv6?
          fc00     = IPAddr.new('fc00::/7')
          fe80     = IPAddr.new('fe80::/10')
          loopback = IPAddr.new('::1/128')

          return fc00.include?(ip) || # Unique Local Addresses
                 fe80.include?(ip) || # Link-local addresses
                 loopback.include?(ip) # Loopback
        end

        false
      rescue IPAddr::InvalidAddressError
        false
      end

      # Determines if a string represents a valid IP address.
      #
      # @param ip_string [String] String to check
      # @return [Boolean] true if the string is a valid IP address
      def valid_ip?(ip_string)
        return false if ip_string.to_s.empty?

        IPAddr.new(ip_string)
        true
      rescue IPAddr::InvalidAddressError
        false
      end
    end

    extend ClassMethods
  end
end

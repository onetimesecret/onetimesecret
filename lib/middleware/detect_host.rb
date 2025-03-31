module Rack

  require 'ipaddr'

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
  # Be cautious when trusting client-provided headers. Ensure that your
  # infrastructure is configured to only allow trusted proxies to set these
  # headers so that clients cannot spoof them. This middleware assumes that
  # the headers come from trusted sources.
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
    # NOTE: CF-Visitor header only contains scheme information { "scheme": "https" }
    # and is not used for host detection
    unless defined?(HEADER_PRECEDENCE)
      # List of HTTP headers that might contain the host, in order of precedence.
      # Headers earlier in the list are given priority over later ones.
      HEADER_PRECEDENCE = [
        'X-Forwarded-Host',   # Common proxy header (AWS ALB, nginx)
        'Apx-Incoming-Host',  # Check Approximated (if it exists)
        'X-Original-Host',    # Various proxy services
        'Forwarded',          # RFC 7239 standard (host parameter)
        'Host',               # Default HTTP host header
      ]

      # Hostnames and IP addresses that should never be accepted as valid hosts.
      # These typically indicate local or development environments.
      INVALID_HOSTS = [
        'localhost',
        'localhost.localdomain',
        '127.0.0.1',
        '::1',
      ].freeze
    end

    attr_reader :logger

    # Class-level setting initialized from ENV variable
    @result_field_name = ENV['DETECTED_HOST'] || 'rack.detected_host'

    class << self
      attr_accessor :result_field_name
    end

    # Initializes the middleware with the application and logging options.
    #
    # @param app [#call] The Rack application
    # @param io [IO] IO object for logging (defaults to stderr)
    # @return [void]
    def initialize(app, io: $stderr)
      @app = app
      log_level = ::Logger::INFO
      # Override with DEBUG level only when conditions are met
      if defined?(OT) && OT.respond_to?(:debug?) && OT.debug?
        log_level = ::Logger::DEBUG
      end
      @logger = ::Logger.new(io, level: log_level)
    end

    # Processes the request and determines the appropriate host.
    #
    # @param env [Hash] Rack environment hash
    # @return [Array] Standard Rack response array from the next middleware
    #
    # This method:
    # 1. Examines headers in order of precedence
    # 2. Normalizes and validates each potential host
    # 3. Accepts the first valid host found
    # 4. Stores the result in env[result_field_name]
    # 5. Passes the request to the next middleware
    def call(env)
      result_field_name = self.class.result_field_name
      detected_host = nil

      # Try headers in order of precedence
      HEADER_PRECEDENCE.each do |header|
        header_key = "HTTP_#{header.tr('-', '_').upcase}"
        host = self.class.normalize_host(env[header_key])
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
        logger.debug("[DetectHost] No valid host detected in request")
      end

      # e.g. env['rack.detected_host'] = 'example.com'
      env[result_field_name] = detected_host

      @app.call(env)
    end

    private

    module ClassMethods
      # Extracts and normalizes the host from a header value.
      #
      # @param value_unsafe [String, nil] Raw header value from the request
      # @return [String, nil] Normalized host without port number, or nil if empty
      #
      # This method:
      # - Takes the first host if multiple are provided (comma-separated)
      # - Removes any port numbers (e.g., example.com:8080 → example.com)
      # - Converts to lowercase and removes surrounding whitespace
      # - Returns nil for empty values
      def normalize_host(value_unsafe)
        host_with_port = value_unsafe.to_s.split(',').first.to_s
        host = host_with_port.split(':').first.to_s.strip.downcase
        return nil if host.empty?
        host
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
        return false if valid_ip?
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
          fc00 = IPAddr.new("fc00::/7")
          fe80 = IPAddr.new("fe80::/10")
          loopback = IPAddr.new("::1/128")

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

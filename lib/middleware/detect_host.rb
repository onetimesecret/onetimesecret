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
      HEADER_PRECEDENCE = [
        'X-Forwarded-Host',   # Common proxy header (AWS ALB, nginx)
        'X-Original-Host',    # Various proxy services
        'Forwarded',          # RFC 7239 standard (host parameter)
        'Host',               # Default HTTP host header
      ]

      INVALID_HOSTS = [
        'localhost',
        'localhost.localdomain',
        '127.0.0.1',
        '::1',
      ].freeze

      IP_PATTERN = /\A(\d{1,3}\.){3}\d{1,3}\z|\A[0-9a-fA-F:]+\z/
    end

    attr_reader :logger

    # Class-level setting initialized from ENV variable
    @result_field_name = ENV['DETECTED_HOST'] || 'rack.detected_host'

    class << self
      attr_accessor :result_field_name
    end

    def initialize(app, io: $stderr)
      @app = app
      log_level = ::Logger::INFO
      # Override with DEBUG level only when conditions are met
      if defined?(OT) && OT.respond_to?(:debug?) && OT.debug?
        log_level = ::Logger::DEBUG
      end
      @logger = ::Logger.new(io, level: log_level)
      logger.info("[DetectHost] Initialized with level #{log_level}")
    end

    def call(env)
      result_field_name = self.class.result_field_name
      detected_host = nil

      # Try headers in order of precedence
      HEADER_PRECEDENCE.each do |header|
        header_key = "HTTP_#{header.tr('-', '_').upcase}"
        host = self.class.normalize_host(env[header_key])
        next if host.nil?

        if self.class.valid_host?(host)
          detected_host = host
          logger.debug("[DetectHost] #{host} via #{header_key}")
          break # stop on first valid host
        else
          logger.debug("[DetectHost] Invalid host detected from #{header_key}: #{host}")
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
      def normalize_host(value_unsafe)
        host_with_port = value_unsafe.to_s.split(',').first.to_s
        host = host_with_port.split(':').first.to_s.strip.downcase
        return nil if host.empty?
        host
      end

      def valid_host?(host)
        return false if INVALID_HOSTS.include?(host)
        return false if host.match?(IP_PATTERN)
        true
      end
    end

    extend ClassMethods
  end
end

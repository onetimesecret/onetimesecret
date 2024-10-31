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
  # The middleware allows setting a class-level `detected_host` variable,
  # which can be initialized from an environment variable `DETECTED_HOST`.
  #
  # ```ruby
  # Rack::DetectHost.detected_host = ENV['DETECTED_HOST'] || 'default_host_value'
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
    HEADER_PRECEDENCE = [
      'X-Forwarded-Host',   # Common proxy header (AWS ALB, nginx)
      'X-Original-Host',    # Various proxy services
      'Forwarded',          # RFC 7239 standard (host parameter)
      'Host'                # Default HTTP host header
    ]

    INVALID_HOSTS = [
      'localhost',
      'localhost.localdomain',
      '127.0.0.1',
      '::1'
    ].freeze

    IP_PATTERN = /\A(\d{1,3}\.){3}\d{1,3}\z|\A[0-9a-fA-F:]+\z/

    attr_reader :logger

    # Class-level setting initialized from ENV variable
    @detected_host = ENV['DETECTED_HOST'] || 'rack.detected_host'

    class << self
      attr_accessor :detected_host
    end

    def initialize(app, io: $stderr)
      @app = app
      @logger = ::Logger.new(io)
    end

    def call(env)
      # Replace rack.detected_host with the class setting
      host = self.class.detected_host

      # Try headers in order of precedence
      HEADER_PRECEDENCE.each do |header|
        header_key = "HTTP_#{header.tr('-', '_').upcase}"
        if env[header_key]
          host = strip_port(env[header_key].split(',').first.strip)
          if valid_host?(host)
            env['rack.detected_host'] = host
            logger.info("[DetectHost] Host detected from #{header}: #{host}")
            break
          else
            logger.debug("[DetectHost] Invalid host detected from #{header}: #{host}")
          end
        else
          logger.debug("[DetectHost] Header not found: #{header}")
        end
      end

      # Log indication if no valid host found in debug mode
      unless env['rack.detected_host']
        logger.debug("[DetectHost] No valid host detected in request")
      end

      @app.call(env)
    end

    private

    def strip_port(host)
      return nil if host.nil? || host.empty?
      host.split(':').first
    end

    def valid_host?(host)
      return false if host.nil? || host.empty?
      return false if INVALID_HOSTS.include?(host.downcase)
      return false if host.match?(IP_PATTERN)
      true
    end
  end
end

module Rack
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

    def initialize(app, io: $stderr)
      @app = app
      @logger = ::Logger.new(io)
    end

    def call(env)
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

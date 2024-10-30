module Rack
  class DetectHost
    # NOTE: CF-Visitor header only contains scheme information { "scheme": "https" }
    # and is not used for host detection
    HEADER_PRECEDENCE = [
      'X-Forwarded-Host',    # Common proxy header (AWS ALB, nginx)
      'X-Original-Host',     # Various proxy services
      'Forwarded',          # RFC 7239 standard (host parameter)
      'Host'                # Default HTTP host header
    ]

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
          env['rack.detected_host'] = env[header_key].split(',').first.strip
          logger.info("[DetectHost] Host detected from #{header}: #{env['rack.detected_host']}")
          break
        else
          logger.debug("[DetectHost] Header not found: #{header}")
        end
      end

      # Fallback to SERVER_NAME if no host found in headers
      unless env['rack.detected_host']
        env['rack.detected_host'] = env['SERVER_NAME']
        logger.info("[DetectHost] Using fallback SERVER_NAME: #{env['rack.detected_host']}")
      end

      @app.call(env)
    end
  end
end

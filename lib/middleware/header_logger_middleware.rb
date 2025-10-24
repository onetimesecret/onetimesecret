# lib/middleware/header_logger_middleware.rb

require_relative 'logging'

# Rack::HeaderLoggerMiddleware
#
# Logs all HTTP headers for each request to the system log.
# It is intended for use in development environments. It is not recommended for
# production use, as it will log sensitive information such as cookies and
# authorization headers. It's particularly helpful for debugging proxies and
# load balancers that may be modifying headers.
#
# SECURITY WARNING: This middleware will log sensitive headers that may contain:
# - Session cookies (Cookie header)
# - Authentication tokens (Authorization header: "Bearer abc123...")
# - API keys (X-Api-Key, X-Auth-Token headers)
# - User tracking data (various custom headers)
# Logs containing this information could be exposed through log aggregation
# systems, shared development environments, or accidental inclusion in bug reports.
#
# To use HeaderLoggerMiddleware, add the following line to your config.ru file
# after the require statements:
#
#     require_relative 'lib/middleware/header_logger_middleware'
#
# And add the following line to the block that sets up your Rack apps:
#
#     use HeaderLoggerMiddleware
#
class Rack::HeaderLoggerMiddleware
  include Middleware::Logging

  def initialize(app, logger: nil)
    @app           = app
    @custom_logger = logger
  end

  def call(env)
    log_headers(env)
    @app.call(env)
  end

  # Override logger to allow custom logger injection
  def logger
    @custom_logger || super
  end

  private

  def log_headers(env)
    logger.info "Request Headers for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}"
    env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
        logger.info "  #{header_name}: #{value}"
      end
    end
  end
end

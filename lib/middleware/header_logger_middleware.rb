require 'logger'

LOGGER = Logger.new(STDOUT) unless defined?(LOGGER)

# Rack::HeaderLoggerMiddleware
#
# Logs all HTTP headers for each request to the system log.
# It is intended for use in development environments. It is not recommended for
# production use, as it will log sensitive information such as cookies and
# authorization headers. It's particularly helpful for debugging proxies and
# load balancers that may be modifying headers.
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
  def initialize(app)
    @app = app
    LOGGER.debug('HeaderLoggerMiddleware initialized')
  end

  def call(env)
    log_headers(env)
    @app.call(env)
  end

  private

  def log_headers(env)
    LOGGER.info("Request Headers for #{env['REQUEST_METHOD']} #{env['PATH_INFO']}:")
    env.each do |key, value|
      if key.start_with?('HTTP_')
        header_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
        LOGGER.info(">  #{header_name}: #{value}")
      end
    end
    LOGGER.info("\n")  # Add a blank line for readability between requests
  end
end

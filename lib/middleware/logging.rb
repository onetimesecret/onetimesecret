# lib/middleware/logging.rb
#
# Provides standardized logging for middleware components.
# Uses SemanticLogger when available, falls back to stdlib Logger.
#
# Usage:
#   class MyMiddleware
#     include Middleware::Logging
#
#     def call(env)
#       logger.debug "Processing request", path: env['PATH_INFO']
#       # ...
#     end
#   end
#
module Middleware
  module Logging
    # Returns a logger instance appropriate for the current context
    # - SemanticLogger with inferred category when available
    # - stdlib Logger to stdout as fallback
    def logger
      @logger ||= initialize_logger
    end

    def initialize_logger
      if defined?(SemanticLogger)
        middleware_name = self.class.name
        SemanticLogger[middleware_name] # e.g. Rack::SessionDebugger
      else
        require 'logger'
        Logger.new($stdout)
      end
    end
  end
end

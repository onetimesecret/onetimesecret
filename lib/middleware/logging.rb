# lib/middleware/logging.rb
#
# Provides standardized logging for middleware components.
# Uses SemanticLogger when available (Onetime context), falls back to stdlib Logger.
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
        category = infer_category
        SemanticLogger[category]
      else
        require 'logger'
        Logger.new($stdout)
      end
    end

    # Infer SemanticLogger category from middleware class name
    # Maps middleware purpose to strategic logging categories
    def infer_category
      class_name = self.class.name.split('::').last

      case class_name
      when /Session/
        'Session'
      when /Auth/
        'Auth'
      when /Security/, /CSRF/, /IPPrivacy/
        'HTTP'
      when /DetectHost/, /RequestId/, /HandleInvalid/, /HeaderLogger/
        'HTTP'
      else
        'App'
      end
    end
  end
end

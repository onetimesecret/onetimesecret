# apps/middleware_stack.rb

require 'rack/content_length'
require 'rack/contrib'
require 'rack/protection'
require 'rack/utf8_sanitizer'

# Character Encoding Configuration
# Set UTF-8 as the default external encoding to ensure consistent text handling:
# - Standardizes file and network I/O operations
# - Normalizes STDIN/STDOUT/STDERR encoding
# - Provides default encoding for strings from external sources
# This prevents encoding-related bugs, especially on fresh OS installations
# where locale settings may not be properly configured.
Encoding.default_external = Encoding::UTF_8

# MiddlewareStack
#
# Standard middleware for all applications
module MiddlewareStack
  class << self
    def configure(builder)
      builder.use Rack::ContentLength
      builder.use Onetime::Middleware::StartupReadiness

      # Apply minimal middleware if config not available
      unless Onetime.conf
        Onetime.ld '[middleware] Configuration not available, using minimal stack'
        return
      end

      # Load the logger early so it's ready to log request errors
      unless Onetime.conf&.dig(:logging, :http_requests).eql?(false)
        builder.use Rack::CommonLogger
      end

      # Error Monitoring Integration
      # Add Sentry exception tracking when available
      # This block only executes if Sentry was successfully initialized
      Onetime.with_diagnostics do |diagnostics_conf|
        Onetime.ld "[config.ru] Sentry enabled #{diagnostics_conf}"
        # Position Sentry middleware early to capture exceptions throughout the stack

        builder.use Sentry::Rack::CaptureExceptions
      end

      # Security Middleware Configuration
      # Configures security-related middleware components based on application settings
      require 'onetime/middleware/security'

      Onetime.ld '[config.ru] Setting up Security middleware'
      builder.use Onetime::Middleware::Security

      # Performance Optimization
      # Support running with code frozen in production-like environments
      # This reduces memory usage and prevents runtime modifications
      if Onetime.conf&.dig(:experimental, :freeze_app).eql?(true)
        Onetime.li "[experimental] Freezing app by request (env: #{Onetime.env})"
        builder.freeze_app
      end
    end

  end
end

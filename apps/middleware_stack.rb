# apps/middleware_stack.rb

require 'rack/content_length'
require 'rack/contrib'
require 'rack/protection'
require 'rack/utf8_sanitizer'

# MiddlewareStack
#
# Standard middleware for all applications
module MiddlewareStack
  def self.configure(builder)

    # Load the logger early so it's ready to log request errors
    unless Onetime.conf.dig(:logging, :http_requests).eql?(false)
      builder.use Rack::CommonLogger
    end

    builder.use Rack::ContentLength

    # Error Monitoring Integration
    # Add Sentry exception tracking when available
    # This block only executes if Sentry was successfully initialized
    Onetime.with_diagnostics do
      Onetime.ld "[config.ru] Sentry enabled"
      # Position Sentry middleware early to capture exceptions throughout the stack

      builder.use Sentry::Rack::CaptureExceptions
    end

    # Environment-specific
    configure_environment(builder)

    # Performance Optimization
    # Support running with code frozen in production-like environments
    # This reduces memory usage and prevents runtime modifications
    if Onetime.conf.dig(:experimental, :freeze_app)
      Onetime.li "[experimental] Freezing app by request (env: #{ENV['RACK_ENV']})"
      builder.freeze_app
    end
  end

  private

  # development/production middleware setup
  def self.configure_environment(builder)

    # Development Environment Configuration
    # Enable development-specific middleware when in development mode
    # This handles code validation and frontend development server integration
    Onetime.development? do
      require 'onetime/middleware/vite_proxy'
      builder.use Onetime::Middleware::ViteProxy
    end

    # Production Environment Configuration
    # Serve static frontend assets in production mode
    # While reverse proxies often handle static files in production,
    # this provides a fallback capability for simpler deployments.
    #
    # Note: This explicit configuration replaces the implicit functionality
    # that existed prior to v0.21.0 release.
    Onetime.production? do
      require 'onetime/middleware/static_files'
      builder.use Onetime::Middleware::StaticFiles

      # Security Middleware Configuration
      # Configures security-related middleware components based on application settings
      require 'onetime/middleware/security'

      Onetime.ld "[config.ru] Setting up Security middleware"
      builder.use Onetime::Middleware::Security
    end

  end
end

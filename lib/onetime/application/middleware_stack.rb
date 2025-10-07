# lib/onetime/application/middleware_stack.rb

require 'rack/content_length'
require 'rack/contrib'
require 'rack/protection'
require 'rack/utf8_sanitizer'

require 'onetime/session'

module Onetime
  module Application
    # MiddlewareStack
    #
    # Standard middleware configuration for all Rack applications
    module MiddlewareStack
      class << self
        def configure(builder, application_context: nil)
          builder.use Rack::ContentLength
          builder.use Onetime::Middleware::StartupReadiness

          # Host detection and identity resolution (common to all apps)
          builder.use Rack::DetectHost

          # Add session middleware early in the stack (before other middleware)
          builder.use Onetime::Session, {
            expire_after: 86_400, # 24 hours
            key: 'onetime.session',
            secure: Onetime.conf&.dig('site', 'ssl'),
            httponly: true,
            same_site: :strict,
            redis_prefix: 'session'
          }

          # Identity resolution middleware (after session)
          builder.use Onetime::Middleware::IdentityResolution

          # Domain strategy middleware (after identity)
          builder.use Onetime::Middleware::DomainStrategy, application_context: application_context

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
  end
end

# lib/onetime/application/middleware_stack.rb

require 'rack/content_length'
require 'rack/contrib'
require 'rack/parser'
require 'rack/protection'
require 'rack/utf8_sanitizer'

require 'onetime/session'
require 'otto'

module Onetime
  module Application
    # MiddlewareStack
    #
    # Standard middleware configuration for all Rack applications
    module MiddlewareStack
      @parsers = {
        'application/json' => proc { |body| Familia::JsonSerializer.parse(body) },
        'application/x-www-form-urlencoded' => proc { |body| Rack::Utils.parse_nested_query(body) },
      }.freeze

      class << self
        # Build locale map for Otto::Locale::Middleware
        #
        # Creates a hash mapping locale codes to language names for all
        # supported locales. Uses English locale file names as the source.
        #
        # @return [Hash<String, String>] Locale code to language name mapping
        def build_available_locales
          # Map of locale codes to language names
          # This could be loaded from locale files in the future
          locale_names = {
            'en' => 'English',
            'ar' => 'العربية',
            'bg' => 'Български',
            'ca_ES' => 'Català',
            'cs' => 'Čeština',
            'da' => 'Dansk',
            'da_DK' => 'Dansk (Danmark)',
            'de' => 'Deutsch',
            'de_AT' => 'Deutsch (Österreich)',
            'el_GR' => 'Ελληνικά',
            'es' => 'Español',
            'fr_CA' => 'Français (Canada)',
            'fr_FR' => 'Français (France)',
            'he' => 'עברית',
            'hu' => 'Magyar',
            'it_IT' => 'Italiano',
            'ja' => '日本語',
            'ko' => '한국어',
            'mi_NZ' => 'Te Reo Māori',
            'nl' => 'Nederlands',
            'pl' => 'Polski',
            'pt_BR' => 'Português (Brasil)',
            'pt_PT' => 'Português (Portugal)',
            'ru' => 'Русский',
            'sl_SI' => 'Slovenščina',
            'sv_SE' => 'Svenska',
            'tr' => 'Türkçe',
            'uk' => 'Українська',
            'vi' => 'Tiếng Việt',
            'zh' => '中文',
          }

          # Return only locales that are in OT.supported_locales
          OT.supported_locales.each_with_object({}) do |locale, result|
            result[locale] = locale_names.fetch(locale, locale)
          end
        end

        # Configure Otto request completion hook for operational metrics
        #
        # Logs every completed request with timing, status, and authentication context.
        # This provides a centralized audit trail for all HTTP requests through Otto.
        #
        def configure_otto_request_hook
          return unless defined?(Otto)

          Otto.on_request_complete do |req, res, duration|
            # Use HTTP logger for request lifecycle events
            logger = SemanticLogger['HTTP']

            # Extract auth context if available
            user_id = req.env['otto.user']&.[](:id)
            strategy_result = req.env['otto.strategy_result']
            auth_strategy = strategy_result&.strategy_name

            logger.info "Request completed",
              method: req.request_method,
              path: req.path,
              status: res.status,
              duration: duration,
              user_id: user_id,
              auth_strategy: auth_strategy,
              ip: req.ip,
              user_agent: req.user_agent&.slice(0, 100)
          end
        end

        def configure(builder, application_context: nil)
          logger = SemanticLogger['App']
          logger.debug "Configuring common middleware",
            application: application_context&.[](:name)

          # Configure Otto request completion hook for operational metrics
          # This provides centralized request logging with timing, status, and auth context
          configure_otto_request_hook

          # IP Privacy FIRST - masks public IPs before logging/monitoring
          # Private/localhost IPs are automatically exempted for development
          # Uses Otto's privacy middleware as a standalone Rack component
          logger.debug "Setting up IP Privacy middleware", note: "masks public IPs"
          builder.use Otto::Security::Middleware::IPPrivacyMiddleware

          builder.use Rack::ContentLength
          builder.use Onetime::Middleware::StartupReadiness

          # Host detection and identity resolution (common to all apps)
          builder.use Rack::DetectHost

          # TODO: Replace with RequestLogger?
          # require 'semantic_logger'
          # SemanticLogger.add_appender(io: $stdout, formatter: :color)

          # adds env['HTTP_X_REQUEST_ID']
          require 'middleware/request_id'
          builder.use Rack::RequestId, generator: -> { Familia.generate_trace_id }

          builder.use Rack::Parser, parsers: @parsers

          # Add session middleware early in the stack (before other middleware)
          builder.use Onetime::Session, {
            secret: Onetime.auth_config.session['secret'],
            expire_after: 86_400, # 24 hours
            secure: Onetime.conf&.dig('site', 'ssl'),
            same_site: :strict,
          }

          # Identity resolution middleware (after session)
          builder.use Onetime::Middleware::IdentityResolution

          # Locale detection middleware (after session, before domain strategy)
          # Sets env['otto.locale'] based on URL param, session, Accept-Language header
          logger.debug "Setting up Locale detection middleware"
          builder.use Otto::Locale::Middleware,
            available_locales: build_available_locales,
            default_locale: OT.default_locale,
            debug: OT.debug?

          # Domain strategy middleware (after identity)
          builder.use Onetime::Middleware::DomainStrategy, application_context: application_context

          # Load the logger early so it's ready to log request errors
          unless Onetime.conf&.dig(:logging, :http_requests).eql?(false)
            logger.debug "Setting up CommonLogger middleware"
            builder.use Rack::CommonLogger
          end

          # Error Monitoring Integration
          # Add Sentry exception tracking when available
          # This block only executes if Sentry was successfully initialized
          Onetime.with_diagnostics do |diagnostics_conf|
            logger.debug "Sentry enabled",
              config: diagnostics_conf
            # Position Sentry middleware early to capture exceptions throughout the stack
            builder.use Sentry::Rack::CaptureExceptions
          end

          # Security Middleware Configuration
          # Configures security-related middleware components based on application settings
          logger.debug "Setting up Security middleware"
          builder.use Onetime::Middleware::Security

          # Performance Optimization
          # Support running with code frozen in production-like environments
          # This reduces memory usage and prevents runtime modifications
          if Onetime.conf&.dig(:experimental, :freeze_app).eql?(true)
            logger.info "Freezing app by request",
              env: Onetime.env
            builder.freeze_app
          end
        end
      end
    end
  end
end

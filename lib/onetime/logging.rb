# frozen_string_literal: true

module Onetime
  # Category-aware logging support for Onetime classes and modules.
  #
  # Provides access to SemanticLogger instances scoped to strategic categories:
  # Auth, Session, HTTP, Familia, Otto, Rhales, Secret, App (default).
  #
  # Usage in classes:
  #   class MyAuthController
  #     include Onetime::Logging
  #
  #     def login
  #       auth_logger.info "Login attempt", email: email, ip: request.ip
  #       # ...
  #     end
  #   end
  #
  # Usage with automatic category detection:
  #   class V2::Logic::Authentication::AuthenticateSession
  #     include Onetime::Logging
  #
  #     def perform
  #       logger.debug "Validating credentials"  # Uses 'Authentication' logger
  #       # ...
  #     end
  #   end
  #
  # Thread-local category override:
  #   def handle_request
  #     with_log_category('HTTP') do
  #       logger.info "Processing request"  # Uses 'HTTP' logger
  #     end
  #   end
  #
  module Logging
    # Returns a SemanticLogger instance scoped to the current class.
    # Attempts to extract a meaningful category from the class name,
    # falling back to 'App' if no match found.
    #
    # @return [SemanticLogger] Logger instance for this class
    #
    def logger
      category = Thread.current[:log_category] || infer_category

      # During early boot before Initializers is extended, get_logger won't exist yet
      # Fall back to uncached logger for early logging, switch to cached after boot
      if Onetime.respond_to?(:get_logger)
        Onetime.get_logger(category)
      else
        SemanticLogger[category]
      end
    end

    # Category-specific logger accessors for explicit context
    # Uses cached logger instances from Onetime::Initializers to preserve level settings
    # Falls back to uncached loggers during early boot before get_logger is available
    def app_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('App') : SemanticLogger['App']
    end

    def auth_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Auth') : SemanticLogger['Auth']
    end

    def familia_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Familia') : SemanticLogger['Familia']
    end

    def http_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('HTTP') : SemanticLogger['HTTP']
    end

    def otto_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Otto') : SemanticLogger['Otto']
    end

    def rhales_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Rhales') : SemanticLogger['Rhales']
    end

    def secret_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Secret') : SemanticLogger['Secret']
    end

    def session_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Session') : SemanticLogger['Session']
    end

    def sequel_logger
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Sequel') : SemanticLogger['Sequel']
    end

    # Execute block with a specific log category via thread-local variable.
    #
    # Enables shared utilities and cross-cutting concerns to log under
    # appropriate operational categories without coupling to specific loggers.
    # Thread-safe - each request/thread maintains independent category context.
    #
    # @param category [String, Symbol] The log category to use
    # @yield Block to execute with the specified category
    #
    # @example Cross-cutting concerns logging under appropriate categories
    #   class RequestProcessor
    #     def handle_auth_request
    #       with_log_category('Auth') do
    #         logger.info "Processing authentication"  # → Auth logs
    #       end
    #     end
    #
    #     def handle_session_request
    #       with_log_category('Session') do
    #         logger.info "Processing session"  # → Session logs
    #       end
    #     end
    #   end
    #
    def with_log_category(category)
      old_category                  = Thread.current[:log_category]
      Thread.current[:log_category] = category.to_s
      yield
    ensure
      Thread.current[:log_category] = old_category
    end

    private

    # Infer log category from class name by checking for known patterns.
    #
    # Maps class names to strategic operational categories, enabling automatic
    # log categorization without manual wiring. Supports monitoring, debugging,
    # and compliance requirements by routing logs to appropriate operational
    # contexts.
    #
    # @return [String] The inferred category name ('App' if no pattern matches)
    #
    def infer_category
      class_name = self.class.name

      # Check for strategic category patterns in class name
      case class_name
      in /Authentication|Auth(?!or)/i
        'Auth'
      in /Familia/i
        'Familia'
      in /HTTP|Request|Response|Controller/i
        'HTTP'
      in /Otto/i
        'Otto'
      in /Rhales/i
        'Rhales'
      in /Secret|Metadata/i
        'Secret'
      in /Sequel/i
        'Sequel'
      in /Session/i
        'Session'
      else
        'App' # default fallback
      end
    end
  end
end

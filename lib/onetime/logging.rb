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
      SemanticLogger[category]
    end

    # Category-specific logger accessors for explicit context
    def auth_logger = SemanticLogger.[]('Auth')
    def session_logger = SemanticLogger.[]('Session')
    def http_logger = SemanticLogger.[]('HTTP')
    def familia_logger = SemanticLogger.[]('Familia')
    def otto_logger = SemanticLogger.[]('Otto')
    def rhales_logger = SemanticLogger.[]('Rhales')
    def secret_logger = SemanticLogger.[]('Secret')
    def app_logger = SemanticLogger.[]('App')

    # Execute block with a specific log category via thread-local variable.
    # Useful for scoping logs within a specific operation context.
    #
    # @param category [String, Symbol] The log category to use
    # @yield Block to execute with the specified category
    #
    # @example
    #   with_log_category('Auth') do
    #     logger.debug "Validating session"
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
    # Maps class names to strategic logging categories.
    #
    # @return [String] The inferred category name
    #
    def infer_category
      class_name = self.class.name

      # Check for strategic category patterns in class name
      return 'Auth'    if class_name =~ /Authentication|Auth(?!or)/i
      return 'Session' if class_name =~ /Session/i
      return 'HTTP'    if class_name =~ /HTTP|Request|Response|Controller/i
      return 'Familia' if class_name =~ /Familia/i
      return 'Otto'    if class_name =~ /Otto/i
      return 'Rhales'  if class_name =~ /Rhales/i
      return 'Secret'  if class_name =~ /Secret|Metadata/i

      # Default fallback
      'App'
    end
  end
end

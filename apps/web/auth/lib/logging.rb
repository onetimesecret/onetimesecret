# frozen_string_literal: true

module Auth
  # Structured logging support for Rodauth authentication system with correlation IDs.
  #
  # Provides consistent logging patterns across all authentication hooks with support
  # for correlation IDs that track requests through multi-step authentication flows
  # (login → MFA → session sync).
  #
  # Usage in Rodauth hooks:
  #   auth.after_login do
  #     Auth::Logging.log_auth_event(
  #       :login_success,
  #       account_id: account_id,
  #       email: account[:email],
  #       correlation_id: session[:auth_correlation_id]
  #     )
  #   end
  #
  # Usage in Operations:
  #   class Auth::Operations::SyncSession
  #     def call
  #       Auth::Logging.log_operation(
  #         :session_sync_start,
  #         account_id: @account_id,
  #         correlation_id: @session[:auth_correlation_id]
  #       )
  #     end
  #   end
  #
  module Logging
    extend self

    # Generate a new correlation ID for tracking an authentication flow
    # @return [String] 12-character random hex string
    def generate_correlation_id
      SecureRandom.hex(6)
    end

    # Log an authentication event with consistent structure
    #
    # @param event [Symbol] Event identifier (e.g., :login_attempt, :login_success, :mfa_required)
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param payload [Hash] Structured data to log
    # @option payload [String] :correlation_id Correlation ID for this auth flow
    # @option payload [Integer] :account_id Rodauth account ID
    # @option payload [String] :email User email (will be obscured)
    # @option payload [String] :ip IP address
    #
    def log_auth_event(event, level: :info, **payload)
      # Obscure email if present
      payload[:email] = OT::Utils.obscure_email(payload[:email]) if payload[:email]

      # Ensure correlation_id is present in payload for visibility
      payload[:correlation_id] ||= 'none'

      logger.public_send(level, "[#{event}]", payload)
    end

    # Log an operation with consistent structure
    #
    # @param operation [Symbol] Operation identifier (e.g., :session_sync, :customer_create)
    # @param level [Symbol] Log level (:debug, :info, :warn, :error)
    # @param payload [Hash] Structured data to log
    #
    def log_operation(operation, level: :info, **payload)
      # Obscure email if present
      payload[:email] = OT::Utils.obscure_email(payload[:email]) if payload[:email]

      # Ensure correlation_id is present
      payload[:correlation_id] ||= 'none'

      logger.public_send(level, "[#{operation}]", payload)
    end

    # Log an error with full exception details
    #
    # @param event [Symbol] Event identifier
    # @param exception [Exception] Exception object
    # @param payload [Hash] Additional structured data
    #
    def log_error(event, exception: nil, **payload)
      # Obscure email if present
      payload[:email] = OT::Utils.obscure_email(payload[:email]) if payload[:email]

      # Ensure correlation_id is present
      payload[:correlation_id] ||= 'none'

      if exception
        logger.error("[#{event}]", exception, payload)
      else
        logger.error("[#{event}]", payload)
      end
    end

    # Log metric data for observability
    #
    # @param metric [Symbol] Metric identifier (e.g., :session_sync_duration, :mfa_setup_success)
    # @param value [Numeric] Metric value
    # @param unit [Symbol] Unit of measurement (e.g., :ms, :count, :percent)
    # @param payload [Hash] Additional structured data
    #
    def log_metric(metric, value:, unit: nil, **payload)
      payload[:metric]           = metric
      payload[:value]            = value
      payload[:unit]             = unit if unit
      payload[:correlation_id] ||= 'none'

      logger.info('[metric]', payload)
    end

    # Measure operation duration and log as metric
    #
    # @param operation [Symbol] Operation identifier
    # @param payload [Hash] Additional structured data
    # @yield Block to measure
    # @return [Object] Result of the block
    #
    # @example
    #   result = Auth::Logging.measure(:session_sync, account_id: 123) do
    #     perform_sync
    #   end
    #
    def measure(operation, **payload)
      start_time  = Onetime.now_in_μs
      result      = yield
      duration_ms = (Onetime.now_in_μs - start_time) / 1000.0

      log_metric(
        :"#{operation}_duration",
        value: duration_ms.round(2),
        unit: :ms,
        **payload,
      )

      result
    end

    private

    # Returns the Auth logger instance
    # @return [SemanticLogger] Logger for Auth category
    def logger
      # Use cached logger if available (after boot), otherwise uncached
      Onetime.respond_to?(:get_logger) ? Onetime.get_logger('Auth') : SemanticLogger['Auth']
    end
  end
end

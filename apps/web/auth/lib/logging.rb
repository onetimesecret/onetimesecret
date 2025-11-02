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
    # @param log_metric [Boolean, Hash] If true, logs a metric with same event name and value=1.
    #   If Hash, uses provided metric options (value, unit, metric_name)
    # @param payload [Hash] Structured data to log
    # @option payload [String] :correlation_id Correlation ID for this auth flow
    # @option payload [Integer] :account_id Rodauth account ID
    # @option payload [String] :email User email (will be obscured)
    # @option payload [String] :ip IP address
    #
    # @example Basic event logging
    #   log_auth_event(:login_attempt, account_id: 123)
    #
    # @example Event with automatic metric
    #   log_auth_event(:login_success, account_id: 123, log_metric: true)
    #   # Logs event + metric with value=1, unit=:count
    #
    # @example Event with custom metric
    #   log_auth_event(:mfa_setup_failure,
    #     failure_reason: :invalid_password,
    #     log_metric: { value: 1, unit: :count }
    #   )
    #
    def log_auth_event(event, level: :info, log_metric: false, **payload)
      # Obscure email if present
      payload[:email] = OT::Utils.obscure_email(payload[:email]) if payload[:email]

      # Ensure correlation_id is present in payload for visibility
      payload[:correlation_id] ||= 'none'

      # e.g. Onetime.auth_logger.info "[login_success]" {...}
      logger.public_send(level, "[#{event}]", payload)

      # Optionally log metric alongside event
      if log_metric
        metric_options = if log_metric.is_a?(Hash)
                          log_metric
                        else
                          { value: 1, unit: :count }
                        end

        # Use custom metric name if provided, otherwise use event name
        metric_name = metric_options.delete(:metric_name) || event

        # Extract metric-specific options and preserve event payload
        metric_payload = payload.dup
        metric_payload.merge!(metric_options.except(:value, :unit))

        self.log_metric(
          metric_name,
          value: metric_options[:value],
          unit: metric_options[:unit],
          **metric_payload
        )
      end
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
      Onetime.get_logger('Auth')
    end
  end
end

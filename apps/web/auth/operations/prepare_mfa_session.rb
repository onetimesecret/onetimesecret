# apps/web/auth/operations/prepare_mfa_session.rb

#
# Prepares the session for MFA (Multi-Factor Authentication) flow.
#
# This operation encapsulates all session mutations required when MFA is
# detected as required. It sets minimal session data needed for the MFA
# verification flow without granting full authenticated access.
#
# Security Principles:
# - Sets only minimal session data (account_id, email, external_id)
# - Sets awaiting_mfa flag to prevent premature access
# - No full session sync until MFA verification completes
# - Validates all inputs before session mutation
# - Idempotent (safe to call multiple times)
#
# Integration:
# - Called from login hook when DetectMfaRequirement returns requires_mfa? = true
# - Complementary to Auth::Operations::SyncSession (deferred until after MFA)
# - Session cleared by logout or MFA timeout
#
# Example:
#   Auth::Operations::PrepareMfaSession.call(
#     session: rack_session,
#     account_id: 123,
#     email: 'user@example.com',
#     external_id: 'cust_abc123',
#     correlation_id: 'auth_xyz789'
#   )
#

module Auth
  module Operations
    class PrepareMfaSession
      # Input validation error
      class InvalidInput < ArgumentError; end

      # @param session [Hash] The Rack session (required)
      # @param account_id [Integer, String] The account ID (required)
      # @param email [String] The account email (required)
      # @param external_id [String, nil] Optional external customer ID
      # @param correlation_id [String, nil] Optional correlation ID for tracking
      # @param logger [Logger, nil] Optional logger for audit trail
      def initialize(session:, account_id:, email:, external_id: nil, correlation_id: nil, logger: nil)
        # Validate inputs
        raise InvalidInput, "session must be present" if session.nil?
        raise InvalidInput, "account_id must be present" if account_id.nil? || account_id.to_s.empty?
        raise InvalidInput, "email must be present" if email.nil? || email.to_s.empty?

        @session = session
        @account_id = account_id.to_i
        @email = email.to_s
        @external_id = external_id&.to_s
        @correlation_id = correlation_id
        @logger = logger || Onetime.get_logger('Auth::PrepareMfaSession')
      end

      # Convenience class method for direct calls
      # @param session [Hash] The Rack session
      # @param account_id [Integer, String] The account ID
      # @param email [String] The account email
      # @param external_id [String, nil] Optional external customer ID
      # @param correlation_id [String, nil] Optional correlation ID
      # @return [Boolean] true if session was prepared successfully
      def self.call(session:, account_id:, email:, external_id: nil, correlation_id: nil)
        new(
          session: session,
          account_id: account_id,
          email: email,
          external_id: external_id,
          correlation_id: correlation_id
        ).call
      end

      # Prepare session for MFA flow
      # @return [Boolean] true if session was prepared successfully
      def call
        # Log session preparation (before mutation)
        @logger.info "Preparing session for MFA flow",
          account_id: @account_id,
          email: OT::Utils.obscure_email(@email),
          has_external_id: !@external_id.nil?,
          correlation_id: @correlation_id,
          module: "PrepareMfaSession"

        # Set MFA flow flag (prevents premature authenticated access)
        @session['awaiting_mfa'] = true

        # Set minimal account data for MFA UI
        @session['account_id'] = @account_id
        @session['email'] = @email

        # Store external_id if present (for customer linkage)
        if @external_id
          @session['external_id'] = @external_id
        end

        # Store correlation ID for flow tracking
        if @correlation_id
          @session[:mfa_correlation_id] = @correlation_id
        end

        # Log successful preparation
        @logger.debug "Session prepared for MFA",
          account_id: @account_id,
          session_keys: session_keys_set,
          correlation_id: @correlation_id,
          module: "PrepareMfaSession"

        true
      end

      private

      # Get list of session keys that were set (for logging)
      # @return [Array<String, Symbol>]
      def session_keys_set
        keys = ['awaiting_mfa', 'account_id', 'email']
        keys << 'external_id' if @external_id
        keys << :mfa_correlation_id if @correlation_id
        keys
      end
    end
  end
end

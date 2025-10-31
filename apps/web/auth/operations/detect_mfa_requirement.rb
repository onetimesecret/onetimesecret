# apps/web/auth/operations/detect_mfa_requirement.rb

#
# Detects whether multi-factor authentication is required for a login session.
#
# This operation is a PURE FUNCTION that makes MFA requirement decisions based
# on primitive inputs only. It has NO external dependencies and receives only
# the minimum information needed to make a security decision.
#
# Security Principles:
# - Accepts only primitive data (no objects, no sessions, no Rodauth)
# - Immutable decision object (frozen)
# - No side effects (no logging, no database access)
# - Validates all inputs
# - Single responsibility: decision logic only
#
# Integration:
# - MFA state is checked by Auth::Operations::MfaStateChecker
# - Session setup is handled by Auth::Operations::PrepareMfaSession
# - Logging is done by the caller (login hook)
#
# Example:
#   decision = Auth::Operations::DetectMfaRequirement.call(
#     account_id: 123,
#     has_otp_secret: true,
#     has_recovery_codes: true
#   )
#   if decision.requires_mfa?
#     # Set up MFA flow
#   end
#

module Auth
  module Operations
    class DetectMfaRequirement
      # Input validation error
      class InvalidInput < ArgumentError; end

      # Decision object returned by the operation
      class Decision
        attr_reader :account_id, :mfa_enabled, :mfa_methods, :reason

        # @param account_id [Integer] The account ID
        # @param mfa_enabled [Boolean] Whether MFA is required
        # @param mfa_methods [Array<Symbol>] Available MFA methods (:otp, :recovery_codes)
        # @param reason [String] Reason for the decision
        def initialize(account_id:, mfa_enabled:, mfa_methods:, reason:)
          @account_id = account_id
          @mfa_enabled = mfa_enabled
          @mfa_methods = mfa_methods.freeze
          @reason = reason

          freeze # Immutable
        end

        # Does the account require MFA?
        # @return [Boolean]
        def requires_mfa?
          @mfa_enabled
        end

        # Should session sync be deferred until after MFA?
        # @return [Boolean]
        def defer_session_sync?
          requires_mfa?
        end

        # Should full session sync proceed immediately?
        # @return [Boolean]
        def sync_session_now?
          !requires_mfa?
        end

        # Primary authentication method to use
        # @return [Symbol, nil] :otp, :recovery_codes, or nil
        def primary_method
          @mfa_methods.first
        end

        # Has OTP as an available method?
        # @return [Boolean]
        def has_otp?
          @mfa_methods.include?(:otp)
        end

        # Has recovery codes as an available method?
        # @return [Boolean]
        def has_recovery_codes?
          @mfa_methods.include?(:recovery_codes)
        end
      end

      # @param account_id [Integer, String] The account ID (required)
      # @param has_otp_secret [Boolean] Whether account has OTP secret configured (required)
      # @param has_recovery_codes [Boolean] Whether account has recovery codes (required)
      # @param mfa_policy [String, Symbol, nil] Optional MFA policy override (:required, :optional, :disabled)
      def initialize(account_id:, has_otp_secret:, has_recovery_codes:, mfa_policy: nil)
        # Validate inputs
        raise InvalidInput, "account_id must be present" if account_id.nil? || account_id.to_s.empty?
        raise InvalidInput, "has_otp_secret must be boolean" unless [true, false].include?(has_otp_secret)
        raise InvalidInput, "has_recovery_codes must be boolean" unless [true, false].include?(has_recovery_codes)

        if mfa_policy && ![:required, :optional, :disabled].include?(mfa_policy.to_sym)
          raise InvalidInput, "mfa_policy must be :required, :optional, :disabled, or nil"
        end

        @account_id = account_id.to_i
        @has_otp_secret = has_otp_secret
        @has_recovery_codes = has_recovery_codes
        @mfa_policy = mfa_policy&.to_sym
      end

      # Convenience class method for direct calls
      # @param account_id [Integer, String] The account ID
      # @param has_otp_secret [Boolean] Whether account has OTP secret configured
      # @param has_recovery_codes [Boolean] Whether account has recovery codes
      # @param mfa_policy [String, Symbol, nil] Optional MFA policy override
      # @return [Decision] The MFA decision object
      def self.call(account_id:, has_otp_secret:, has_recovery_codes:, mfa_policy: nil)
        new(
          account_id: account_id,
          has_otp_secret: has_otp_secret,
          has_recovery_codes: has_recovery_codes,
          mfa_policy: mfa_policy
        ).call
      end

      # Executes the MFA detection operation
      # @return [Decision] The MFA decision object
      def call
        Decision.new(
          account_id: @account_id,
          mfa_enabled: mfa_required?,
          mfa_methods: available_methods,
          reason: decision_reason
        )
      end

      private

      # Determines if MFA is required
      # @return [Boolean]
      def mfa_required?
        # Check policy override first
        return true if @mfa_policy == :required
        return false if @mfa_policy == :disabled

        # Default behavior: require MFA only if OTP is configured
        # Recovery codes alone are not sufficient - they're only valid as backup for OTP
        # Orphaned recovery codes (without OTP) indicate incomplete MFA setup
        @has_otp_secret
      end

      # Get list of available MFA methods
      # @return [Array<Symbol>]
      def available_methods
        methods = []
        methods << :otp if @has_otp_secret
        methods << :recovery_codes if @has_recovery_codes
        methods
      end

      # Get reason for decision
      # @return [String]
      def decision_reason
        return 'policy_required' if @mfa_policy == :required
        return 'policy_disabled' if @mfa_policy == :disabled
        return 'no_mfa_configured' unless mfa_required?

        if @has_otp_secret && @has_recovery_codes
          'otp_and_recovery_configured'
        elsif @has_otp_secret
          'otp_configured'
        elsif @has_recovery_codes
          'recovery_codes_only'
        else
          'no_mfa_configured'
        end
      end
    end
  end
end

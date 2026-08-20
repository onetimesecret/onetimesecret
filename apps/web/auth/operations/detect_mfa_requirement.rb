# apps/web/auth/operations/detect_mfa_requirement.rb
#
# frozen_string_literal: true

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
        # @param mfa_methods [Array<Symbol>] Available MFA methods (:otp, :webauthn, :recovery_codes)
        # @param reason [String] Reason for the decision
        def initialize(account_id:, mfa_enabled:, mfa_methods:, reason:)
          @account_id  = account_id
          @mfa_enabled = mfa_enabled
          @mfa_methods = mfa_methods.freeze
          @reason      = reason

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
        # @return [Symbol, nil] :otp, :webauthn, :recovery_codes, or nil
        def primary_method
          @mfa_methods.first
        end

        # Has OTP as an available method?
        # @return [Boolean]
        def has_otp?
          @mfa_methods.include?(:otp)
        end

        # Has WebAuthn (passkey / security key) as an available method?
        # @return [Boolean]
        def has_webauthn?
          @mfa_methods.include?(:webauthn)
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
      # @param has_webauthn [Boolean] Whether account has WebAuthn credentials (passkeys /
      #   security keys). Defaults to false so existing callers keep their behavior; the
      #   caller is responsible for passing true ONLY when the webauthn feature is loaded
      #   (an account must never be gated on a factor it cannot complete).
      # @param mfa_policy [String, Symbol, nil] Optional MFA policy override (:required, :optional, :disabled)
      # @param via_omniauth [Boolean] Whether the login is via SSO/OmniAuth. When true, MFA is bypassed:
      #   the IdP is trusted to enforce authentication factors (project policy: SSO ignores MFA).
      # @param via_webauthn_login [Boolean] Whether the FIRST factor of this login was a
      #   WebAuthn credential (POST /auth/webauthn-login — rodauth's authenticated_by
      #   contains 'webauthn' in after_login). When true, MFA is bypassed: the passkey IS
      #   one of the account's second factors, so demanding it (or any other factor) again
      #   is unsatisfiable — Rodauth's webauthn-auth route rejects a repeat of the login
      #   type (require_two_factor_not_authenticated type-match), which would loop the
      #   login forever. Project policy: a passkey (possession + local gesture) fully
      #   authenticates, even when the account also has OTP.
      def initialize(account_id:, has_otp_secret:, has_recovery_codes:, has_webauthn: false,
                     mfa_policy: nil, via_omniauth: false, via_webauthn_login: false)
        # Validate inputs
        raise InvalidInput, 'account_id must be present' if account_id.nil? || account_id.to_s.empty?
        raise InvalidInput, 'has_otp_secret must be boolean' unless [true, false].include?(has_otp_secret)
        raise InvalidInput, 'has_recovery_codes must be boolean' unless [true, false].include?(has_recovery_codes)
        raise InvalidInput, 'has_webauthn must be boolean' unless [true, false].include?(has_webauthn)
        raise InvalidInput, 'via_omniauth must be boolean' unless [true, false].include?(via_omniauth)
        raise InvalidInput, 'via_webauthn_login must be boolean' unless [true, false].include?(via_webauthn_login)

        if mfa_policy && ![:required, :optional, :disabled].include?(mfa_policy.to_sym)
          raise InvalidInput, 'mfa_policy must be :required, :optional, :disabled, or nil'
        end

        @account_id         = account_id.to_i
        @has_otp_secret     = has_otp_secret
        @has_recovery_codes = has_recovery_codes
        @has_webauthn       = has_webauthn
        @mfa_policy         = mfa_policy&.to_sym
        @via_omniauth       = via_omniauth
        @via_webauthn_login = via_webauthn_login
      end

      # Convenience class method for direct calls
      # @param account_id [Integer, String] The account ID
      # @param has_otp_secret [Boolean] Whether account has OTP secret configured
      # @param has_recovery_codes [Boolean] Whether account has recovery codes
      # @param has_webauthn [Boolean] Whether account has WebAuthn credentials
      # @param mfa_policy [String, Symbol, nil] Optional MFA policy override
      # @param via_omniauth [Boolean] Whether the login is via SSO/OmniAuth
      # @param via_webauthn_login [Boolean] Whether the first factor was a passkey
      # @return [Decision] The MFA decision object
      def self.call(account_id:, has_otp_secret:, has_recovery_codes:, has_webauthn: false,
                    mfa_policy: nil, via_omniauth: false, via_webauthn_login: false)
        new(
          account_id: account_id,
          has_otp_secret: has_otp_secret,
          has_recovery_codes: has_recovery_codes,
          has_webauthn: has_webauthn,
          mfa_policy: mfa_policy,
          via_omniauth: via_omniauth,
          via_webauthn_login: via_webauthn_login,
        ).call
      end

      # Executes the MFA detection operation
      # @return [Decision] The MFA decision object
      def call
        Decision.new(
          account_id: @account_id,
          mfa_enabled: mfa_required?,
          mfa_methods: available_methods,
          reason: decision_reason,
        )
      end

      private

      # Determines if MFA is required
      # @return [Boolean]
      def mfa_required?
        # SSO logins bypass MFA: the IdP is trusted to enforce authentication
        # factors. This is checked BEFORE policy overrides because the project
        # policy is "SSO ignores MFA" — if an account is configured to require
        # MFA but the user authenticates via SSO, the IdP's factors satisfy that.
        return false if @via_omniauth

        # Passkey-first logins bypass MFA: the WebAuthn credential just used IS
        # one of the account's second factors. Demanding a second factor here is
        # at best redundant (OTP after a passkey) and at worst unsatisfiable —
        # Rodauth's webauthn-auth completion route rejects re-use of the login
        # type, so a webauthn-only account would loop forever. Checked before
        # policy overrides for the same reason as via_omniauth: the factor that
        # a :required policy demands has already been presented.
        return false if @via_webauthn_login

        # Check policy override first
        return true if @mfa_policy == :required
        return false if @mfa_policy == :disabled

        # Default behavior: require MFA if any completable second factor is
        # configured — an OTP secret, a WebAuthn credential, or recovery codes.
        # Recovery codes alone are not sufficient as PRIMARY setup — they're
        # only valid as backup — but orphaned codes still gate the login
        # (preserved pre-webauthn behavior).
        @has_otp_secret || @has_recovery_codes || @has_webauthn
      end

      # Get list of available MFA methods. Order matters: primary_method is
      # first, and the login hook keeps OTP as the primary UX when present;
      # webauthn ranks above recovery codes (a real factor above the backup).
      # @return [Array<Symbol>]
      def available_methods
        methods = []
        methods << :otp if @has_otp_secret
        methods << :webauthn if @has_webauthn
        methods << :recovery_codes if @has_recovery_codes
        methods
      end

      # Get reason for decision. Legacy strings (otp_*, recovery_codes_only)
      # are preserved verbatim so log/monitoring queries keep matching.
      # @return [String]
      def decision_reason
        return 'sso_bypass' if @via_omniauth
        return 'webauthn_login_bypass' if @via_webauthn_login
        return 'policy_required' if @mfa_policy == :required
        return 'policy_disabled' if @mfa_policy == :disabled
        return 'no_mfa_configured' unless mfa_required?

        if @has_otp_secret && @has_webauthn
          'otp_and_webauthn_configured'
        elsif @has_webauthn && @has_recovery_codes
          'webauthn_and_recovery_configured'
        elsif @has_webauthn
          'webauthn_configured'
        elsif @has_otp_secret && @has_recovery_codes
          'otp_and_recovery_configured'
        elsif @has_otp_secret
          'otp_configured'
        else
          'recovery_codes_only'
        end
      end
    end
  end
end

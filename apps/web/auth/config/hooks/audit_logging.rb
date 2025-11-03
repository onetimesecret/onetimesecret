# apps/web/auth/config/hooks/audit_logging.rb

module Auth::Config::Hooks
  module AuditLogging
    def self.configure(auth)
      # ========================================================================
      # MFA Setup Events
      # ========================================================================

      auth.audit_log_message_for :otp_setup, "MFA enabled via TOTP"
      auth.audit_log_metadata_for :otp_setup do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          correlation_id: session[:auth_correlation_id] || 'none',
          mfa_method: 'totp',
          recovery_codes_count: respond_to?(:recovery_codes) ? recovery_codes.length : 0,
          hmac_enabled: otp_keys_use_hmac?,
        }
      end

      auth.audit_log_message_for :otp_disable, "MFA disabled"
      auth.audit_log_metadata_for :otp_disable do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          mfa_method: 'totp',
        }
      end

      # ========================================================================
      # MFA Verification Events
      # ========================================================================

      auth.audit_log_message_for :two_factor_auth_success do
        "MFA verification successful via TOTP"
      end
      auth.audit_log_metadata_for :two_factor_auth_success do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          correlation_id: session[:auth_correlation_id] || 'none',
          mfa_method: 'totp',
        }
      end

      auth.audit_log_message_for :otp_auth_failure do
        "MFA verification failed - invalid code"
      end
      auth.audit_log_metadata_for :otp_auth_failure do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          correlation_id: session[:auth_correlation_id] || 'none',
          mfa_method: 'totp',
          failure_reason: 'invalid_code',
        }
      end

      # ========================================================================
      # Recovery Code Events
      # ========================================================================

      auth.audit_log_message_for :add_recovery_codes, "Recovery codes generated"
      auth.audit_log_metadata_for :add_recovery_codes do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          codes_count: respond_to?(:recovery_codes) ? recovery_codes.length : 0,
        }
      end

      auth.audit_log_message_for :view_recovery_codes, "Recovery codes viewed"
      auth.audit_log_metadata_for :view_recovery_codes do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          security_note: 'User accessed recovery codes - potential security event',
        }
      end

      auth.audit_log_message_for :recovery_auth do
        "Authenticated via recovery code"
      end
      auth.audit_log_metadata_for :recovery_auth do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          correlation_id: session[:auth_correlation_id] || 'none',
          mfa_method: 'recovery_code',
          security_note: 'Recovery code used - primary MFA unavailable',
        }
      end

      # ========================================================================
      # Login/Logout Events
      # ========================================================================

      auth.audit_log_message_for :login do
        mfa_required = otp_exists?
        if mfa_required
          "Login successful - MFA required"
        else
          "Login successful"
        end
      end
      auth.audit_log_metadata_for :login do
        metadata = {
          ip: request.ip,
          user_agent: request.user_agent,
          correlation_id: session[:auth_correlation_id] || 'none',
          mfa_required: otp_exists?,
        }

        # Add recovery codes info if feature is enabled
        if respond_to?(:recovery_codes_available?)
          metadata[:has_recovery_codes] = recovery_codes_available?
        end

        metadata
      end

      auth.audit_log_message_for :login_failure do
        "Login failed - invalid credentials"
      end
      auth.audit_log_metadata_for :login_failure do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          email: param_or_nil('login') || param_or_nil('email'),
          failure_reason: 'invalid_credentials',
        }
      end

      auth.audit_log_message_for :logout, "Logout"
      auth.audit_log_metadata_for :logout do
        {
          ip: request.ip,
          user_agent: request.user_agent,
        }
      end

      # ========================================================================
      # Password Events
      # ========================================================================

      auth.audit_log_message_for :change_password, "Password changed"
      auth.audit_log_metadata_for :change_password do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          initiated_by: 'user',
        }
      end

      auth.audit_log_message_for :reset_password_request do
        "Password reset requested"
      end
      auth.audit_log_metadata_for :reset_password_request do
        {
          ip: request.ip,
          user_agent: request.user_agent,
        }
      end

      auth.audit_log_message_for :reset_password, "Password reset completed"
      auth.audit_log_metadata_for :reset_password do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          initiated_by: 'password_reset_flow',
        }
      end

      # ========================================================================
      # Account Management Events
      # ========================================================================

      auth.audit_log_message_for :create_account, "Account created"
      auth.audit_log_metadata_for :create_account do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          email: account[:email],
        }
      end

      auth.audit_log_message_for :verify_account, "Account verified"
      auth.audit_log_metadata_for :verify_account do
        {
          ip: request.ip,
          user_agent: request.user_agent,
        }
      end

      auth.audit_log_message_for :close_account, "Account closed"
      auth.audit_log_metadata_for :close_account do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          reason: 'user_initiated',
        }
      end

      # ========================================================================
      # Account Lockout Events
      # ========================================================================

      auth.audit_log_message_for :account_lockout do
        "Account locked due to failed login attempts"
      end
      auth.audit_log_metadata_for :account_lockout do
        {
          ip: request.ip,
          user_agent: request.user_agent,
          lockout_reason: 'max_failed_attempts',
        }
      end

      # ========================================================================
      # Events to Skip Logging
      # ========================================================================
      #
      # Set message to nil for events we don't want in the audit log.
      # These are too noisy or not security-relevant.
      #

      # Skip session management events (too noisy)
      auth.audit_log_message_for :active_sessions, nil
    end
  end
end

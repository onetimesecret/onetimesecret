# apps/web/auth/config/rodauth_overrides.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Placeholder for Rodauth overrides
  #
  module RodauthOverrides
    def self.configure(auth)

      # Override authenticated? to require MFA completion
      # auth.auth_class_eval do
      #   def require_authentication
      #     if session[:awaiting_mfa]
      #       set_redirect_error_flash require_mfa_error_flash
      #       redirect otp_auth_route
      #     end
      #     super
      #   end
      # end

      # # Override OTP validation instance method
      # auth.auth_class_eval do
      #   # Store original method
      #   alias_method :_original_otp_valid_code?, :otp_valid_code?

      #   # TODO: Do we still need this now that we've resolved the
      #   # context issues with how we organized the code?
      #   #
      #   def otp_valid_code?(oacode)
      #     # Always log when this method is called
      #     Onetime.auth_logger.debug '[MFA] otp_valid_code? called',
      #       code: oacode,
      #       json: json_request?,
      #       post: request.post?,
      #       path: request.path_info,
      #       setup_route: otp_setup_route,
      #       auth_route: otp_auth_route,
      #       session_raw: session[:otp_setup_raw]

      #     # Otherwise use default validation
      #     _original_otp_valid_code?(oacode)
      #   end
      # end

      # # Custom: Get WebAuthn credentials list for account
      # # Used by frontend to show registered devices
      # auth_class_eval do
      #   def webauthn_credentials_for_account
      #     db[webauthn_keys_table]
      #       .where(webauthn_keys_account_id_column => account_id)
      #       .select(
      #         Sequel.as(webauthn_keys_webauthn_id_column, :id),
      #         webauthn_keys_last_use_column,
      #         webauthn_keys_sign_count_column
      #       )
      #       .all
      #   end
      # end

    end
  end
end

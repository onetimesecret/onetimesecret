# apps/web/auth/config/features/email_auth.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Email Auth feature: passwordless login via email links (aka magic links).
  # Users receive a time-limited link to sign in without a password.
  #
  # ENV: ENABLE_EMAIL_AUTH (default: disabled, set to 'true' to enable)
  #
  module EmailAuth
    using Familia::Refinements::TimeLiterals

    def self.configure(auth)
      auth.enable :email_auth

      # Magic links are only valid for a short period so we also keep
      # the resend interval short to avoid user frustration.
      auth.email_auth_deadline_interval 15.minutes
      auth.email_auth_skip_resend_email_within 30.seconds

      # Email content is configured in config/email/email_auth.rb
      # using the MagicLink template class for proper i18n support.

      # JSON API response configuration
      # In JSON mode, flash methods automatically become JSON responses
      auth.email_auth_request_error_flash 'Error requesting login link'
      auth.email_auth_email_sent_notice_flash 'Login link sent to your email'
      auth.email_auth_email_recently_sent_error_flash 'Login link was recently sent, please check your email'
      auth.email_auth_error_flash 'Login link has expired or is invalid'

      # Routes (relative to /auth mount point)
      auth.email_auth_route 'email-login'
      auth.email_auth_request_route 'email-login-request'

      # Session key for storing token during auth flow
      auth.email_auth_session_key 'email_auth_key'
    end
  end
end

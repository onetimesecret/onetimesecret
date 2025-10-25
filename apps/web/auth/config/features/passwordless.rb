# apps/web/auth/config/features/passwordless.rb

module Auth::Config::Features
  # Passwordless (Email Magic Links) feature configuration
  #
  module Passwordless
    using Familia::Refinements::TimeLiterals

    def self.configure(auth)

      # Email Auth (Magic Links)
      # enable :email_auth

      # Table and column configuration
      # All Rodauth tables use account_id as FK, not id
      auth.email_auth_table :account_email_auth_keys
      auth.email_auth_id_column :account_id
      auth.email_auth_key_column :key
      auth.email_auth_deadline_column :deadline
      auth.email_auth_email_last_sent_column :email_last_sent

      # Magic links are only valid for a short period so we also keep
      # the resend interval short to avoid user frustration.
      auth.email_auth_deadline_interval 15.minutes
      auth.email_auth_skip_resend_email_within 30.seconds

      # Email content for magic links
      auth.email_auth_email_subject 'Login Link'
      auth.email_auth_email_body do
        <<~EMAIL
          Hello,

          You requested a login link for your OneTimeSecret account.

          Click the link below to sign in:

          #{email_auth_email_link}

          This link will expire in 15 minutes.

          If you didn't request this, you can safely ignore this email.

          Best regards,
          The OneTimeSecret Team
        EMAIL
      end

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

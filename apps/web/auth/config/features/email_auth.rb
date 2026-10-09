# apps/web/auth/config/features/email_auth.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  # Email Auth feature: passwordless login via email links (aka magic links).
  # Users receive a time-limited link to sign in without a password.
  #
  # ENV: AUTH_EMAIL_AUTH_ENABLED (default: disabled, set to 'true' to enable)
  #
  module EmailAuth
    using Familia::Refinements::TimeLiterals

    def self.configure(auth)
      auth.enable :email_auth

      # Magic links are only valid for a short period so we also keep
      # the resend interval short to avoid user frustration. The interval
      # is a Sequel date_add hash, the form Rodauth's own default takes.
      auth.email_auth_deadline_interval({ minutes: 15 })
      auth.email_auth_skip_resend_email_within 30.seconds

      # Write the deadline when the key row is created (#4689,
      # RISK-2026-08-14-M02). Rodauth only writes it when
      # set_deadline_values? is true, which by default is MySQL only, so on
      # PostgreSQL and SQLite the 24-hour column default applied instead.
      # set_deadline_values? is Rodauth-wide (it also covers the
      # reset_password and lockout keys), so it stays off and only this
      # table gets an explicit deadline.
      #
      # A resend inside the deadline reuses the existing row: Rodauth's
      # create_email_auth_key only touches email_last_sent and emails the same
      # key, so the deadline written here is never extended. A request after
      # the deadline deletes the expired row and inserts a fresh one.
      #
      # Same expression as the column default (DB clock), so it compares
      # cleanly with Rodauth's `CURRENT_TIMESTAMP > deadline` check.
      # use_date_arithmetic? loads Sequel's date_arithmetic extension, which
      # Sequel.date_add needs; active_sessions loads it too when enabled.
      auth.use_date_arithmetic? true
      auth.email_auth_key_insert_hash do
        # Explicit `super()`: Rodauth config blocks become define_method bodies,
        # where implicit-argument super is not allowed.
        hash = super()
        hash[email_auth_deadline_column] = Sequel.date_add(
          Sequel::CURRENT_TIMESTAMP, email_auth_deadline_interval
        )
        hash
      end

      # Email template configuration (must be after enable :email_auth)
      Auth::Config::Email::EmailAuth.configure(auth)

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

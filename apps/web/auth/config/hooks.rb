# apps/web/auth/config/hooks.rb
#
#
# Hooks supported:
#   before_create_account_route
#   before_create_account
#   before_login_attempt
#   after_login
#   after_login_failure
#   before_logout
#   after_logout
#   before_reset_password_request_route
#   after_reset_password_request
#   before_reset_password_route
#   after_reset_password
#   before_change_password_route
#   after_change_password
#   before_close_account_route
#   after_close_account
#   before_verify_account_route
#   after_verify_account
#   before_otp_setup_route
#   before_otp_auth_route
#   after_account_lockout
#
# Hook execution order:
#   before_*_route → validation.rb hooks → before_* → after_*
#
# Log levels:
#   OT.li - Normal operations, attempts, successes
#   OT.le   - Security events, failures, lockouts
#
# Logs authentication events for debugging and security monitoring.
# Emails obscured. No passwords, tokens, or keys logged.

module Auth
  module Config
    module Hooks
      require_relative 'hooks/account_lifecycle'
      require_relative 'hooks/authentication'
      require_relative 'hooks/session_integration'
      require_relative 'hooks/rate_limiting'
      require_relative 'hooks/validation'
    end
  end
end

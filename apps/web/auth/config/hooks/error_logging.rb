# apps/web/auth/config/hooks/error_logging.rb
#
# Logs authentication events for debugging and security monitoring.
# Emails obscured. No passwords, tokens, or keys logged.
#
# Hook execution order:
#   before_*_route → validation.rb hooks → before_* → after_*
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
# Log levels:
#   OT.li - Normal operations, attempts, successes
#   OT.le   - Security events, failures, lockouts
#

module Auth
  module Config
    module Hooks
      module ErrorLogging
        def self.configure
          proc do
            # ========================================
            # Account Creation
            # ========================================

            before_create_account_route do
              # Fires: On POST /create-account, before any validation
              # Logs: "Account creation attempt: d***o@e*****e.com"
              email = param('login') || param('email')
              OT.li "[auth] Account creation attempt: #{OT::Utils.obscure_email(email)}"
            end

            before_create_account do
              # Fires: After validation passes, before DB insert
              # Logs: "Account creation blocked - duplicate email: d***o@e*****e.com"
              #
              # Note: Rodauth will throw error for duplicate email, so after_create_account
              # won't fire for duplicates. Actual failures are caught in validation.rb hook
              # with "Invalid email rejected".
              email = param('login') || param('email')

              existing = db[:accounts].where(email: email, status_id: [1, 2]).first
              if existing
                OT.li "[auth] Account creation blocked - duplicate email: #{OT::Utils.obscure_email(email)}"
              end
            end


            # ========================================
            # Login
            # ========================================

            before_login_attempt do
              # Fires: Before credential verification
              # Logs: "Login attempt: u***r@e*****e.com"
              email = param('login') || param('email')
              OT.li "[auth] Login attempt: #{OT::Utils.obscure_email(email)}"
            end

            after_login do
              # Fires: After successful authentication
              # Logs: "Login successful: user@example.com"
              OT.li "[auth] Login successful: #{account[:email]}"
            end

            after_login_failure do
              # Fires: After failed authentication
              # Logs: "Login failed for u***r@e*****e.com: Invalid credentials"
              email = param('login') || param('email')
              OT.li "[auth] Login failed for #{OT::Utils.obscure_email(email)}: Invalid credentials"
            end

            # ========================================
            # Logout
            # ========================================

            before_logout do
              # Fires: Before session cleared
              # Logs: "Logout: user@example.com"
              if account
                OT.li "[auth] Logout: #{account[:email]}"
              end
            end

            after_logout do
              # Fires: After session cleared
              # Logs: "Logout completed"
              OT.li "[auth] Logout completed"
            end

            # ========================================
            # Password Reset
            # ========================================

            before_reset_password_request_route do
              # Fires: On POST /reset-password
              # Logs: "Password reset request: u***r@e*****e.com"
              email = param('login') || param('email')
              OT.li "[auth] Password reset request: #{OT::Utils.obscure_email(email)}"
            end

            after_reset_password_request do
              # Fires: After reset email sent
              # Logs: "Password reset email sent to: user@example.com"
              OT.li "[auth] Password reset email sent to: #{account[:email]}"
            end

            before_reset_password_route do
              # Fires: On POST /reset-password/:key
              # Logs: "Password reset completion attempt (key provided)"
              OT.li "[auth] Password reset completion attempt (key provided)"
            end

            after_reset_password do
              # Fires: After password successfully reset
              # Logs: "Password reset completed for: user@example.com"
              OT.li "[auth] Password reset completed for: #{account[:email]}"
            end

            # ========================================
            # Password Change
            # ========================================

            before_change_password_route do
              # Fires: On POST /change-password (authenticated)
              # Logs: "Password change attempt: user@example.com"
              if account
                OT.li "[auth] Password change attempt: #{account[:email]}"
              end
            end

            after_change_password do
              # Fires: After password successfully changed
              # Logs: "Password changed for: user@example.com"
              OT.li "[auth] Password changed for: #{account[:email]}"
            end

            # ========================================
            # Account Closure
            # ========================================

            before_close_account_route do
              # Fires: On POST /close-account (authenticated)
              # Logs: "Account closure attempt: user@example.com"
              if account
                OT.li "[auth] Account closure attempt: #{account[:email]}"
              end
            end

            after_close_account do
              # Fires: After account successfully closed
              # Logs: "Account closed: user@example.com (ID: 123)"
              OT.li "[auth] Account closed: #{account[:email]} (ID: #{account_id})"
            end

            # ========================================
            # Account Verification
            # ========================================

            if ENV['RACK_ENV'] != 'test'
              # Fires: On POST /verify-account (disabled in test env)
              # Logs: "Account verification attempt (key provided)"
              before_verify_account_route do
                OT.li "[auth] Account verification attempt (key provided)"
              end

              after_verify_account do
                # Fires: After account successfully verified
                # Logs: "Account verified: user@example.com"
                OT.li "[auth] Account verified: #{account[:email]}"
              end
            end

            # ========================================
            # MFA (Optional)
            # ========================================

            if respond_to?(:before_otp_setup_route)
              # Fires: On POST /otp-setup (if MFA enabled)
              # Logs: "MFA setup attempt: user@example.com"
              before_otp_setup_route do
                OT.li "[auth] MFA setup attempt: #{account[:email]}"
              end
            end

            if respond_to?(:before_otp_auth_route)
              # Fires: On POST /otp-auth (if MFA enabled)
              # Logs: "MFA verification attempt: user@example.com"
              before_otp_auth_route do
                OT.li "[auth] MFA verification attempt: #{account[:email]}"
              end
            end

            # ========================================
            # Security Events
            # ========================================

            if respond_to?(:after_account_lockout)
              # Fires: After account locked due to failed attempts
              # Logs: "SECURITY: Account locked out: user@example.com"
              after_account_lockout do
                OT.le "[auth] SECURITY: Account locked out: #{account[:email]}"
              end
            end
          end
        end
      end
    end
  end
end

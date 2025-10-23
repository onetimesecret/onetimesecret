# apps/web/auth/config/hooks/mfa.rb

module Auth
  module Config
    module Hooks
      module MFA
        def self.configure(auth)

          #
          # Hook: After OTP Authentication
          #
          # This hook is triggered after successful two-factor (OTP) authentication.
          # Complete the full session sync that was deferred during login.
          #
          auth.after_otp_auth do
            OT.info "[auth] OTP authentication successful for: #{account[:email]}"

            if session['mfa_pending']
              OT.info "[auth] Completing deferred session sync after MFA"
              Onetime::ErrorHandler.safe_execute('sync_session_after_mfa',
                account_id: account_id,
                email: account[:email],
              ) do
                Handlers.sync_session_after_login(account, account_id, session, request)
                session.delete('mfa_pending')
              end
            end
          end

        end
      end
    end
  end
end

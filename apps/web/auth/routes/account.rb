# apps/web/auth/routes/account.rb

module Auth
  module Routes
    module Account
      def handle_account_routes(r)
        # Account info endpoint (JSON extension support)
        r.get 'account.json' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = rodauth.account

            # Check if MFA features are enabled before calling methods
            mfa_enabled          = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?
            recovery_codes_count = if rodauth.respond_to?(:recovery_codes_available)
              rodauth.recovery_codes_available
            else
              0
            end

            # Get active sessions count
            active_sessions_count = rodauth.db[:account_active_session_keys]
              .where(account_id: account[:id])
              .count

            {
              id: account[:id],
              email: account[:email],
              created_at: account[:created_at],
              status: account[:status_id],
              email_verified: account[:status_id] == 2,  # Assuming 2 is verified
              mfa_enabled: mfa_enabled,
              recovery_codes_count: recovery_codes_count,
              active_sessions_count: active_sessions_count,
            }
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end

        # MFA status endpoint
        r.get 'mfa-status' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            rodauth.account_from_session

            # Check if MFA features are enabled
            enabled = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?

            # Get last_use timestamp from account_otp_keys table if MFA is enabled
            last_used_at = nil
            if enabled
              otp_record   = rodauth.db[:account_otp_keys]
                .where(id: rodauth.account_id)
                .first
              last_used_at = otp_record[:last_use]&.iso8601 if otp_record
            end

            # Get count of unused recovery codes (if recovery codes feature is enabled)
            recovery_codes_remaining = if rodauth.respond_to?(:recovery_codes_available)
              rodauth.recovery_codes_available
            else
              0
            end

            response.headers['Content-Type'] = 'application/json'
            {
              enabled: enabled,
              last_used_at: last_used_at,
              recovery_codes_remaining: recovery_codes_remaining,
            }
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end

        # Account info endpoint
        r.get 'account' do
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = rodauth.account_from_session

            # Check if MFA features are enabled before calling methods
            mfa_enabled          = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?
            recovery_codes_count = if rodauth.respond_to?(:recovery_codes_available)
              rodauth.recovery_codes_available
            else
              0
            end

            # Get active sessions count
            active_sessions_count = rodauth.db[:account_active_session_keys]
              .where(account_id: account[:id])
              .count

            {
              id: account[:id],
              email: account[:email],
              created_at: account[:created_at],
              status: account[:status_id],
              email_verified: account[:status_id] == 2,  # Assuming 2 is verified
              mfa_enabled: mfa_enabled,
              recovery_codes_count: recovery_codes_count,
              active_sessions_count: active_sessions_count,
            }
          rescue StandardError => ex
            puts "Error: #{ex.class} - #{ex.message}"
            puts ex.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
        end
      end
    end
  end
end

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
            # Query database directly instead of using rodauth.recovery_codes.size
            recovery_codes_count = if rodauth.respond_to?(:recovery_codes_available?)
              rodauth.db[:account_recovery_codes]
                .where(id: account[:id])
                .count
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

            # Check if MFA features are enabled (OTP or recovery codes)
            #
            # NOTE: We check for the method first b/c it only exists while the
            # feature is enabled. Otherwise this would raise a MethodNotFound error.
            has_otp = rodauth.respond_to?(:otp_exists?) && rodauth.otp_exists?

            # Get count of unused recovery codes by querying the database directly
            # Note: Don't use rodauth.recovery_codes.size as it may auto-generate codes
            # when auto_add_recovery_codes? is true, creating phantom codes
            recovery_codes_remaining = if rodauth.respond_to?(:recovery_codes_available?)
              rodauth.db[:account_recovery_codes]
                .where(id: rodauth.account_id)
                .count
            else
              0
            end

            # MFA is enabled if either OTP is setup OR recovery codes exist
            enabled = has_otp || recovery_codes_remaining > 0

            # Get last_use timestamp from account_otp_keys table if OTP is enabled
            last_used_at = nil
            if has_otp
              otp_record   = rodauth.db[:account_otp_keys]
                .where(id: rodauth.account_id)
                .first
              last_used_at = otp_record[:last_use]&.iso8601 if otp_record
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
            # Query database directly instead of using rodauth.recovery_codes.size
            recovery_codes_count = if rodauth.respond_to?(:recovery_codes_available?)
              rodauth.db[:account_recovery_codes]
                .where(id: account[:id])
                .count
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

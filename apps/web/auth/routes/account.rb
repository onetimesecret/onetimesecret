# frozen_string_literal: true

module Auth
  module Routes
    module Account
      def handle_account_routes(r)
        # Account info endpoint (JSON extension support)
        r.get 'account.json' do
          begin
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = rodauth.account
            {
              id: account[:id],
              email: account[:email],
              created_at: account[:created_at],
              status: account[:status_id],
              email_verified: account[:status_id] == 2,  # Assuming 2 is verified
              mfa_enabled: rodauth.otp_exists?,
              recovery_codes_count: rodauth.recovery_codes_available
            }
          rescue => e
            puts "Error: #{e.class} - #{e.message}"
            puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
          end
        end

        # Account info endpoint
        r.get 'account' do
          begin
            unless rodauth.logged_in?
              response.status = 401
              next { error: 'Authentication required' }
            end

            account = rodauth.account

            {
              id: account[:id],
              email: account[:email],
              created_at: account[:created_at],
              status: account[:status_id],
              email_verified: account[:status_id] == 2,  # Assuming 2 is verified
              mfa_enabled: rodauth.otp_exists?,
              recovery_codes_count: rodauth.recovery_codes_available
            }
          rescue => e
            puts "Error: #{e.class} - #{e.message}"
            puts e.backtrace.join("\n") if ENV['RACK_ENV'] == 'development'

            response.status = 500
            { error: 'Internal server error' }
          end
        end
      end
    end
  end
end

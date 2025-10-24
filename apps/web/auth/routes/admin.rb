# apps/web/auth/routes/admin.rb

module Auth
  module Routes
    module Admin
      def handle_admin_routes(r)
        # Administrative endpoints (if needed)
        r.on 'admin' do
          # Add admin authentication here

          r.get 'stats' do
              db = Auth::Config::Database.connection
              {
                total_accounts: db[:accounts].count,
                verified_accounts: db[:accounts].where(status_id: 2).count,
                active_sessions: db[:account_active_session_keys].count,
                mfa_enabled_accounts: db[:account_otp_keys].count,
                unused_recovery_codes: db[:account_recovery_codes].where(used_at: nil).count,
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
end

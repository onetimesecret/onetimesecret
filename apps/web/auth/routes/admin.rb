# apps/web/auth/routes/admin.rb

module Auth
  module Routes
    module Admin
      def handle_admin_routes(r)
        # Admin endpoints (if needed)
        r.on('admin') do
          # Add admin authentication here
          r.get('stats') do
              db = Auth::Database.connection
              if db
                {
                  total_accounts: db[:accounts].count,
                  verified_accounts: db[:accounts].where(status_id: 2).count,
                  active_sessions: db[:account_active_session_keys].count,
                  mfa_enabled_accounts: db[:account_otp_keys].count,
                  unused_recovery_codes: db[:account_recovery_codes].where(used_at: nil).count,
                  mode: 'advanced',
                }
              else
                {
                  mode: 'basic',
                  message: 'Stats not available',
                }
              end
            rescue StandardError => ex
              auth_logger.error 'Auth stats endpoint error', exception: ex
              response.status = 500
              { error: 'Internal server error' }
          end
        end
      end
    end
  end
end

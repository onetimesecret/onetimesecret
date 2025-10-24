# apps/web/auth/routes/health.rb

module Auth
  module Routes
    module Health
      def handle_health_routes(r)
        r.get 'health' do
            # Test database connection
            db_status = Auth::Config::Database.connection.test_connection ? 'ok' : 'error'

            {
              status: 'ok',
              timestamp: Familia.now, # UTC in seconds (float)
              database: db_status,
              version: Onetime::VERSION,
            }
          rescue StandardError => ex
            response.status = 503
            {
              status: 'error',
              error: ex.message,
              timestamp: Familia.now, # UTC in seconds (float)
            }
        end
      end
    end
  end
end

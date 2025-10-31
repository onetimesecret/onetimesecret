# apps/web/auth/routes/health.rb

module Auth
  module Routes
    module Health
      def handle_health_routes(r)

        # Health check endpoint
        r.on('health') do
          r.get do
              # Test database connection if in advanced mode
              db_status = if Auth::Database.connection
                Auth::Database.connection.test_connection ? 'ok' : 'error'
              else
                'not_required'
              end

              {
                status: 'ok',
                timestamp: Familia.now.to_i,
                database: db_status,
                version: Onetime::VERSION,
                mode: Onetime.auth_config.mode,
              }
            rescue StandardError => ex
              response.status = 503
              {
                status: 'error',
                error: ex.message,
                timestamp: Familia.now.to_i,
              }
          end
        end

      end
    end
  end
end

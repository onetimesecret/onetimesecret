# apps/web/core/controllers/health.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Health
      include Base

      def index
        res['content-type'] = 'application/json'
        res.body            = JSON.generate(
          status: 'ok',
          timestamp: Familia.now.to_i,
          version: Onetime::VERSION,
        )
      end

      # Advanced health check - detailed status of all connections
      # Only accessible from localhost/private networks (via middleware)
      def advanced
        checks = {
          redis: check_redis,
          database: check_database,
        }

        overall_status = checks.values.all? { |c| c[:status] == 'ok' } ? 'ok' : 'degraded'

        res['content-type'] = 'application/json'
        res.body            = JSON.generate(
          status: overall_status,
          timestamp: Familia.now.to_i,
          version: Onetime::VERSION,
          checks: checks,
        )
      end

      private

      def check_redis
        # Familia uses Redis - test connection with PING
        redis  = Familia.redis
        result = redis.ping
        {
          status: result == 'PONG' ? 'ok' : 'error',
          latency_ms: nil, # Could add timing if needed
        }
      rescue StandardError => ex
        {
          status: 'error',
          error: ex.message,
        }
      end

      def check_database
        # Auth database is optional (only in advanced auth mode)
        return { status: 'not_configured' } unless defined?(Auth::Database)

        connection = Auth::Database.connection
        return { status: 'not_configured' } unless connection

        {
          status: connection.test_connection ? 'ok' : 'error',
          mode: Onetime.auth_config.mode,
        }
      rescue StandardError => ex
        {
          status: 'error',
          error: ex.message,
        }
      end
    end
  end
end

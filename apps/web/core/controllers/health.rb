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
          rabbitmq: check_rabbitmq,
          database: check_database,
        }

        # RabbitMQ and database are optional - only count configured services
        required_checks = checks.reject { |_, v| v[:status] == 'not_configured' }
        overall_status  = required_checks.values.all? { |c| c[:status] == 'ok' } ? 'ok' : 'degraded'

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

      def check_rabbitmq
        # RabbitMQ is optional - check if configured
        amqp_url = ENV.fetch('RABBITMQ_URL', nil)
        return { status: 'not_configured' } if amqp_url.nil? || amqp_url.empty?

        require 'bunny'
        conn = Bunny.new(amqp_url)
        conn.start

        {
          status: conn.open? ? 'ok' : 'error',
          vhost: conn.vhost,
        }
      rescue LoadError
        { status: 'not_configured' }
      rescue StandardError => ex
        {
          status: 'error',
          error: ex.message,
        }
      ensure
        conn&.close if defined?(conn) && conn
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

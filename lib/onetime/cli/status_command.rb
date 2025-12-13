# lib/onetime/cli/status_command.rb
#
# frozen_string_literal: true

#
# CLI command for checking system-wide service status
#
# Usage:
#   ots status [options]
#
# Options:
#   -f, --format FORMAT    Output format: text or json (default: text)
#   -w, --watch SECONDS    Watch mode with refresh interval
#   -q, --quiet            Only show services with issues
#
# Examples:
#   ots status
#   ots status --format json
#   ots status --watch 5
#   ots status --quiet
#

require 'json'
require 'net/http'
require 'socket'

module Onetime
  module CLI
    class StatusCommand < Command
      desc 'Show system-wide service status'

      option :format, type: :string, default: 'text', aliases: ['f'],
        desc: 'Output format: text or json'
      option :watch, type: :integer, aliases: ['w'],
        desc: 'Watch mode with refresh interval in seconds'
      option :quiet, type: :boolean, default: false, aliases: ['q'],
        desc: 'Only show services with issues'

      def call(format: 'text', watch: nil, quiet: false, **)
        @boot_error = nil

        begin
          boot_application!
          @boot_success = true
        rescue StandardError => ex
          @boot_success = false
          @boot_error = ex.message
        end

        if watch
          watch_mode(watch, format, quiet)
        else
          display_status(format, quiet)
        end
      end

      private

      def watch_mode(interval, format, quiet)
        loop do
          system('clear') if format == 'text'
          display_status(format, quiet)
          sleep interval
        end
      rescue Interrupt
        puts "\nExiting watch mode..."
        exit 0
      end

      def display_status(format, quiet)
        status = collect_status

        case format
        when 'json'
          puts JSON.pretty_generate(status)
        else
          display_text_status(status, quiet)
        end
      end

      # ─────────────────────────────────────────────────────────────────────
      # Status Collection
      # ─────────────────────────────────────────────────────────────────────

      def collect_status
        # Check services first (worker check needs rabbitmq data)
        rabbitmq_status = check_rabbitmq

        {
          timestamp: Time.now.utc.iso8601,
          environment: environment,
          auth_mode: auth_mode,
          boot: {
            success: @boot_success,
            error: @boot_error,
          },
          services: {
            redis: check_redis,
            auth_database: check_auth_database,
            rabbitmq: rabbitmq_status,
          },
          processes: {
            puma: check_puma,
            vite: check_vite,
            worker: check_worker(rabbitmq_status),
            scheduler: check_scheduler,
          },
        }
      end

      def environment
        ENV['RACK_ENV'] || 'development'
      end

      def auth_mode
        OT.auth_config&.mode || 'simple'
      end

      def jobs_enabled?
        OT.conf.dig('jobs', 'enabled') == true
      end

      # ─────────────────────────────────────────────────────────────────────
      # Database Checks
      # ─────────────────────────────────────────────────────────────────────

      def check_redis
        pool = Onetime::Runtime.infrastructure.database_pool
        return { status: 'error', error: 'No connection pool' } unless pool

        pool.with do |conn|
          info = conn.info('server')
          uri = Familia.uri
          parsed = parse_redis_uri(uri)

          {
            status: 'connected',
            host: parsed[:host],
            port: parsed[:port],
            db: parsed[:db],
            pool_size: pool.size,
            models: Familia.members.size,
            version: info['redis_version'],
          }
        end
      rescue StandardError => ex
        { status: 'error', error: ex.message }
      end

      def parse_redis_uri(uri)
        parsed = URI.parse(uri.to_s)
        {
          host: parsed.host || '127.0.0.1',
          port: parsed.port || 6379,
          db: parsed.path&.delete('/')&.to_i || 0,
        }
      rescue StandardError
        { host: 'unknown', port: 0, db: 0 }
      end

      def check_auth_database
        unless OT.auth_config&.full_enabled?
          return { status: 'not_required', enabled: false }
        end

        require 'sequel'
        db_url = OT.auth_config.database_url
        db = Sequel.connect(db_url)

        adapter = db.adapter_scheme.to_s
        version = case adapter
                  when 'sqlite'
                    db.fetch('SELECT sqlite_version() as v').first[:v]
                  when 'postgres'
                    db.fetch('SELECT version()').first[:version].split.first(2).join(' ')
                  else
                    'unknown'
                  end

        db.disconnect

        {
          status: 'connected',
          enabled: true,
          adapter: adapter,
          version: version,
          url: sanitize_db_url(db_url),
        }
      rescue StandardError => ex
        { status: 'error', enabled: true, error: ex.message }
      end

      def sanitize_db_url(url)
        return url if url.start_with?('sqlite')

        url.gsub(%r{://([^:@]+):([^@]+)@}, '://\1:***@')
      end

      # ─────────────────────────────────────────────────────────────────────
      # Message Queue Checks
      # ─────────────────────────────────────────────────────────────────────

      def check_rabbitmq
        unless jobs_enabled?
          return { status: 'not_required', enabled: false }
        end

        require 'bunny'

        url = OT.conf.dig('jobs', 'rabbitmq_url') || ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
        conn = Bunny.new(url)
        conn.start

        queue_info = check_queue_depths(conn)
        total_pending = queue_info.values.sum { |q| q[:messages] || 0 }

        result = {
          status: 'connected',
          enabled: true,
          host: conn.host,
          port: conn.port,
          vhost: conn.vhost,
          queue_count: queue_info.size,
          pending_messages: total_pending,
          queues: queue_info,
        }

        conn.close
        result
      rescue StandardError => ex
        { status: 'error', enabled: true, error: ex.message }
      end

      def check_queue_depths(conn)
        require_relative '../jobs/queue_config'

        channel = conn.create_channel
        queues = {}

        Onetime::Jobs::QueueConfig::QUEUES.each_key do |queue_name|
          queue = channel.queue(queue_name, durable: true, passive: true)
          queues[queue_name] = {
            messages: queue.message_count,
            consumers: queue.consumer_count,
          }
        rescue Bunny::NotFound
          queues[queue_name] = { error: 'not found' }
        end

        channel.close
        queues
      rescue StandardError
        {}
      end

      # ─────────────────────────────────────────────────────────────────────
      # Process Checks (connectivity-based, not PID-based)
      # ─────────────────────────────────────────────────────────────────────

      def check_puma
        port = ENV.fetch('PORT', 3000).to_i
        host = ENV.fetch('HOST', '127.0.0.1')

        uri = URI("http://#{host}:#{port}/api/v2/status")
        response = Net::HTTP.get_response(uri)

        { status: 'running', port: port, http_status: response.code.to_i }
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
        { status: 'stopped', port: port }
      rescue StandardError => ex
        { status: 'error', error: ex.class.name }
      end

      def check_vite
        return { status: 'not_required' } unless environment == 'development'

        port = ENV.fetch('VITE_PORT', 5173).to_i
        host = '127.0.0.1'

        # Vite dev server responds to HTTP
        uri = URI("http://#{host}:#{port}/")
        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 1
        http.read_timeout = 1
        response = http.head(uri.path.empty? ? '/' : uri.path)

        { status: 'running', port: port }
      rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Net::OpenTimeout, Net::ReadTimeout
        { status: 'stopped', port: port }
      rescue StandardError => ex
        { status: 'error', error: ex.class.name }
      end

      def check_worker(rabbitmq_status)
        unless jobs_enabled?
          return { status: 'not_required', enabled: false }
        end

        # Workers register as consumers on RabbitMQ queues
        queues = rabbitmq_status.dig(:queues) || {}
        total_consumers = queues.values.sum { |q| q[:consumers] || 0 }

        if total_consumers.positive?
          { status: 'running', consumers: total_consumers }
        else
          { status: 'stopped', consumers: 0 }
        end
      rescue StandardError => ex
        { status: 'error', error: ex.message }
      end

      def check_scheduler
        unless jobs_enabled?
          return { status: 'not_required', enabled: false }
        end

        # Check for scheduler heartbeat in Redis
        pool = Onetime::Runtime.infrastructure.database_pool
        return { status: 'unknown', reason: 'no redis' } unless pool

        pool.with do |conn|
          heartbeat_key = 'ots:scheduler:heartbeat'
          last_heartbeat = conn.get(heartbeat_key)

          if last_heartbeat
            age_seconds = Time.now.to_i - last_heartbeat.to_i
            if age_seconds < 120 # Consider alive if heartbeat within 2 minutes
              { status: 'running', last_heartbeat_ago: age_seconds }
            else
              { status: 'stopped', last_heartbeat_ago: age_seconds, stale: true }
            end
          else
            { status: 'stopped', reason: 'no heartbeat' }
          end
        end
      rescue StandardError => ex
        { status: 'error', error: ex.message }
      end

      # ─────────────────────────────────────────────────────────────────────
      # Text Output
      # ─────────────────────────────────────────────────────────────────────

      def display_text_status(status, quiet)
        lines = []

        # Header line with boot status
        boot = status[:boot]
        boot_indicator = boot[:success] ? "\u2713" : "\u2717"

        lines << format('ots status | %s | %s auth | %s boot | %s',
          status[:environment],
          status[:auth_mode],
          boot_indicator,
          status[:timestamp],
        )

        # Show boot error if present
        lines << format('  Boot error: %s', boot[:error]) if boot[:error]

        lines << ''

        # Databases section
        db_lines = format_databases(status[:services], quiet)
        unless db_lines.empty?
          lines << 'Databases'
          lines.concat(db_lines)
          lines << ''
        end

        # Message Queue section
        mq_lines = format_message_queue(status[:services], quiet)
        unless mq_lines.empty?
          lines << 'Message Queue'
          lines.concat(mq_lines)
          lines << ''
        end

        # Processes section
        proc_lines = format_processes(status[:processes], quiet)
        unless proc_lines.empty?
          lines << 'Processes'
          lines.concat(proc_lines)
        end

        puts lines.join("\n")
      end

      def format_databases(services, quiet)
        lines = []

        # Redis
        redis = services[:redis]
        unless quiet && redis[:status] == 'connected'
          lines << format_service_line('Redis', redis_status_text(redis), redis[:status])
        end

        # Auth DB
        auth_db = services[:auth_database]
        unless quiet && %w[connected not_required].include?(auth_db[:status])
          lines << format_service_line('Auth DB', auth_db_status_text(auth_db), auth_db[:status])
        end

        lines
      end

      def format_message_queue(services, quiet)
        lines = []

        rmq = services[:rabbitmq]
        unless quiet && %w[connected not_required].include?(rmq[:status])
          lines << format_service_line('RabbitMQ', rabbitmq_status_text(rmq), rmq[:status])
        end

        lines
      end

      def format_processes(processes, quiet)
        lines = []

        processes.each do |name, info|
          next if quiet && info[:status] == 'running'
          next if quiet && info[:status] == 'not_required'

          lines << format_service_line(name.to_s.capitalize, process_status_text(name, info), info[:status])
        end

        lines
      end

      def format_service_line(name, detail, status)
        indicator = status_indicator(status)
        format('  %s %-12s %s', indicator, name, detail)
      end

      def status_indicator(status)
        case status
        when 'connected', 'running'
          "\u2713" # ✓
        when 'not_required'
          "\u25CB" # ○
        else
          "\u2717" # ✗
        end
      end

      def redis_status_text(info)
        case info[:status]
        when 'connected'
          format('%s:%d/%d (pool: %d, models: %d)',
            info[:host], info[:port], info[:db],
            info[:pool_size], info[:models],
          )
        when 'error'
          info[:error]
        else
          'unknown'
        end
      end

      def auth_db_status_text(info)
        case info[:status]
        when 'connected'
          format('%s %s', info[:adapter], info[:version])
        when 'not_required'
          'not required'
        when 'error'
          info[:error]
        else
          'unknown'
        end
      end

      def rabbitmq_status_text(info)
        case info[:status]
        when 'connected'
          format('%s:%d (%d queues, %d pending)',
            info[:host], info[:port],
            info[:queue_count], info[:pending_messages],
          )
        when 'not_required'
          'not required'
        when 'error'
          info[:error]
        else
          'unknown'
        end
      end

      def process_status_text(name, info)
        case info[:status]
        when 'running'
          case name
          when :puma
            format('port %d', info[:port])
          when :vite
            format('port %d', info[:port])
          when :worker
            format('%d consumers', info[:consumers])
          when :scheduler
            format('heartbeat %ds ago', info[:last_heartbeat_ago])
          else
            'running'
          end
        when 'stopped'
          case name
          when :puma, :vite
            format('port %d not responding', info[:port])
          when :worker
            'no consumers'
          when :scheduler
            info[:stale] ? format('stale heartbeat (%ds)', info[:last_heartbeat_ago]) : 'no heartbeat'
          else
            'stopped'
          end
        when 'not_required'
          'not required'
        when 'unknown'
          info[:reason] || 'unknown'
        when 'error'
          info[:error]
        else
          'unknown'
        end
      end
    end

    register 'status', StatusCommand
  end
end

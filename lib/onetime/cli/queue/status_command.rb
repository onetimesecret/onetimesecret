# lib/onetime/cli/queue/status_command.rb
#
# frozen_string_literal: true

#
# CLI command for checking job system status
#
# Usage:
#   ots queue status [options]
#
# Options:
#   -f, --format FORMAT    Output format: text or json (default: text)
#   -w, --watch SECONDS    Watch mode with refresh interval
#

require 'bunny'
require 'json'
require 'net/http'
require 'uri'
require_relative '../../jobs/queues/config'
require_relative 'rabbitmq_helpers'

module Onetime
  module CLI
    module Queue
      class StatusCommand < Command
        desc 'Show job system status'

        include Onetime::CLI::Queue::RabbitMQHelpers

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'
        option :watch,
          type: :integer,
          aliases: ['w'],
          desc: 'Watch mode with refresh interval in seconds'

        def call(format: 'text', watch: nil, **)
          boot_application!

          if watch
            watch_mode(watch, format)
          else
            display_status(format)
          end
        end

        private

        def watch_mode(interval, format)
          loop do
            system('clear') if format == 'text'
            display_status(format)
            sleep interval
          end
        rescue Interrupt
          puts "\nExiting watch mode..."
          exit 0
        end

        def display_status(format)
          status = collect_status

          case format
          when 'json'
            puts JSON.pretty_generate(status)
          else
            display_text_status(status)
          end
        end

        def collect_status
          status = {
            timestamp: Time.now.utc.iso8601,
            rabbitmq: check_rabbitmq_connection,
            exchanges: {},
            queues: {},
            dlq_policies: check_dlq_policies,
            scheduler: check_scheduler,
          }

          # Get exchange and queue info if RabbitMQ is available
          if status[:rabbitmq][:connected]
            status[:exchanges] = check_exchanges
            status[:queues]    = check_queue_depths
          end

          status
        end

        def check_rabbitmq_connection
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          conn     = Bunny.new(amqp_url)
          conn.start

          {
            connected: true,
            url: mask_amqp_credentials(amqp_url),
            vhost: conn.vhost,
            heartbeat: conn.heartbeat,
          }
        rescue StandardError => ex
          {
            connected: false,
            error: ex.message,
          }
        ensure
          conn&.close
        end

        def check_queue_depths
          conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start

          queues = {}

          # Use actual queue names from QueueConfig
          # Each queue check needs its own channel because Bunny::NotFound closes the channel
          Onetime::Jobs::QueueConfig::QUEUES.each_key do |queue_name|
              channel            = conn.create_channel
              queue              = channel.queue(queue_name, durable: true, passive: true)
              queues[queue_name] = {
                messages: queue.message_count,
                consumers: queue.consumer_count,
              }
              channel.close
          rescue Bunny::NotFound
              queues[queue_name] = { error: 'Queue not found' }
          rescue StandardError => ex
              queues[queue_name] = { error: ex.message }
          end

          queues
        rescue StandardError => ex
          { error: ex.message }
        ensure
          conn&.close
        end

        def check_exchanges
          conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start

          exchanges = {}

          # Check dead letter exchanges from QueueConfig
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.each_key do |exchange_name|
              channel                  = conn.create_channel
              # Use passive: true to check if exchange exists without creating it
              channel.exchange(exchange_name, type: :fanout, durable: true, passive: true)
              exchanges[exchange_name] = { exists: true, type: 'fanout', durable: true }
              channel.close
          rescue Bunny::NotFound
              exchanges[exchange_name] = { exists: false, error: 'Exchange not found' }
          rescue StandardError => ex
              exchanges[exchange_name] = { exists: false, error: ex.message }
          end

          exchanges
        rescue StandardError => ex
          { error: ex.message }
        ensure
          conn&.close
        end

        def check_workers
          pid_path = ENV.fetch('SNEAKERS_PID_PATH', 'tmp/pids/sneakers.pid')

          if File.exist?(pid_path)
            pid = File.read(pid_path).strip.to_i
            begin
              Process.kill(0, pid)
              { running: true, pid: pid }
            rescue Errno::ESRCH
              { running: false, stale_pid: pid }
            end
          else
            { running: false }
          end
        rescue StandardError => ex
          { error: ex.message }
        end

        def check_scheduler
          pid_path = ENV.fetch('SCHEDULER_PID_PATH', 'tmp/pids/scheduler.pid')

          if File.exist?(pid_path)
            pid = File.read(pid_path).strip.to_i
            begin
              Process.kill(0, pid)
              { running: true, pid: pid }
            rescue Errno::ESRCH
              { running: false, stale_pid: pid }
            end
          else
            { running: false }
          end
        rescue StandardError => ex
          { error: ex.message }
        end

        def check_dlq_policies
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          parsed   = parse_amqp_url(amqp_url)
          vhost    = URI.encode_www_form_component(parsed[:vhost])

          uri      = URI.parse("#{management_url}/api/policies/#{vhost}")
          user, pw = management_credentials

          http              = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = uri.scheme == 'https'
          http.open_timeout = 3
          http.read_timeout = 5

          request = Net::HTTP::Get.new(uri.request_uri)
          request.basic_auth(user, pw)

          response = http.request(request)

          return [] unless response.code.to_i == 200

          policies = JSON.parse(response.body)
          policies.select { |p| p['pattern']&.include?('dlq') }
        rescue StandardError
          # Management API unavailable or error — not critical for status
          nil
        end

        def format_ttl(ms)
          seconds = ms / 1000
          if seconds >= 86_400
            format('%dms (%dd)', ms, seconds / 86_400)
          elsif seconds >= 3600
            format('%dms (%dh)', ms, seconds / 3600)
          else
            format('%dms', ms)
          end
        end

        # rubocop:disable Metrics/PerceivedComplexity -- Display method with inherent branching
        def display_text_status(status)
          puts '═' * 80
          puts 'Onetime Job System Status'
          puts '═' * 80
          puts
          puts format('Timestamp: %s', status[:timestamp])
          puts

          # RabbitMQ Status
          puts 'RabbitMQ Connection:'
          if status[:rabbitmq][:connected]
            puts format('  Status: Connected')
            puts format('  URL: %s', status[:rabbitmq][:url])
            puts format('  VHost: %s', status[:rabbitmq][:vhost])
            puts format('  Heartbeat: %ds', status[:rabbitmq][:heartbeat])
          else
            puts format('  Status: Disconnected')
            puts format('  Error: %s', status[:rabbitmq][:error])
          end
          puts

          # Exchanges
          puts 'Exchanges:'
          if status[:exchanges].empty?
            puts '  No exchange information available'
          elsif status[:exchanges][:error]
            puts format('  Error: %s', status[:exchanges][:error])
          else
            status[:exchanges].each do |exchange_name, info|
              if info.is_a?(Hash) && info[:exists]
                puts format('  %s: %s, durable=%s', exchange_name, info[:type], info[:durable])
              elsif info.is_a?(Hash) && info[:error]
                puts format('  %s: %s', exchange_name, info[:error])
              elsif info.is_a?(Hash)
                puts format('  %s: not found', exchange_name)
              end
            end
          end
          puts

          # Queue Depths
          puts 'Queue Depths:'
          if status[:queues].empty?
            puts '  No queue information available'
          elsif status[:queues][:error]
            # Top-level error from check_queue_depths
            puts format('  Error: %s', status[:queues][:error])
          else
            status[:queues].each do |queue_name, info|
              if info.is_a?(Hash) && info[:error]
                puts format('  %s: %s', queue_name, info[:error])
              elsif info.is_a?(Hash)
                puts format(
                  '  %s: %d messages, %d consumers',
                  queue_name,
                  info[:messages],
                  info[:consumers],
                )
              end
            end
          end
          puts

          # DLQ Policies
          puts 'DLQ Policies:'
          if status[:dlq_policies].nil?
            puts '  Management API unavailable'
          elsif status[:dlq_policies].empty?
            puts '  none'
          else
            status[:dlq_policies].each do |policy|
              ttl_ms      = policy.dig('definition', 'message-ttl')
              ttl_display = ttl_ms ? format_ttl(ttl_ms) : 'n/a'
              puts format(
                '  %s  pattern=%s  message-ttl=%s',
                policy['name'],
                policy['pattern'],
                ttl_display,
              )
            end
          end
          puts

          # Scheduler
          puts 'Scheduler:'
          if status[:scheduler][:running]
            puts format('  Status: Running (PID %d)', status[:scheduler][:pid])
          elsif status[:scheduler][:stale_pid]
            puts format('  Status: Stopped (stale PID %d)', status[:scheduler][:stale_pid])
          else
            puts '  Status: Stopped'
          end
          puts
          puts '═' * 80
        end
        # rubocop:enable Metrics/PerceivedComplexity
      end
    end

    register 'queue status', Queue::StatusCommand
    register 'queues status', Queue::StatusCommand  # Alias
  end
end

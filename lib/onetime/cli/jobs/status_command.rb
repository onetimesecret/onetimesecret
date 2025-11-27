# lib/onetime/cli/jobs/status_command.rb
#
# frozen_string_literal: true

#
# CLI command for checking job system status
#
# Usage:
#   ots jobs status [options]
#
# Options:
#   -f, --format FORMAT    Output format: text or json (default: text)
#   -w, --watch SECONDS    Watch mode with refresh interval
#

require 'bunny'
require 'json'

module Onetime
  module CLI
    module Jobs
      class StatusCommand < Command
        desc 'Show job system status'

        option :format, type: :string, default: 'text', aliases: ['f'],
          desc: 'Output format: text or json'
        option :watch, type: :integer, aliases: ['w'],
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
            queues: {},
            workers: check_workers,
            scheduler: check_scheduler
          }

          # Get queue depths if RabbitMQ is available
          if status[:rabbitmq][:connected]
            status[:queues] = check_queue_depths
          end

          status
        end

        def check_rabbitmq_connection
          conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start

          info = {
            connected: true,
            url: ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672').gsub(/:[^:@]+@/, ':***@'),
            vhost: conn.vhost,
            heartbeat: conn.heartbeat
          }

          conn.close
          info
        rescue StandardError => e
          {
            connected: false,
            error: e.message
          }
        end

        def check_queue_depths
          conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start
          channel = conn.create_channel

          queues = {}

          # Known queues - could be auto-discovered from worker classes
          %w[email notifications default].each do |queue_name|
            begin
              queue = channel.queue(queue_name, durable: true, passive: true)
              queues[queue_name] = {
                messages: queue.message_count,
                consumers: queue.consumer_count
              }
            rescue Bunny::NotFound
              queues[queue_name] = { error: 'Queue not found' }
            end
          end

          conn.close
          queues
        rescue StandardError => e
          { error: e.message }
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
        rescue StandardError => e
          { error: e.message }
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
        rescue StandardError => e
          { error: e.message }
        end

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

          # Queue Depths
          puts 'Queue Depths:'
          if status[:queues].empty?
            puts '  No queue information available'
          else
            status[:queues].each do |queue_name, info|
              if info[:error]
                puts format('  %s: %s', queue_name, info[:error])
              else
                puts format('  %s: %d messages, %d consumers',
                           queue_name, info[:messages], info[:consumers])
              end
            end
          end
          puts

          # Workers
          puts 'Workers:'
          if status[:workers][:running]
            puts format('  Status: Running (PID %d)', status[:workers][:pid])
          elsif status[:workers][:stale_pid]
            puts format('  Status: Stopped (stale PID %d)', status[:workers][:stale_pid])
          else
            puts '  Status: Stopped'
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
      end
    end

    register 'jobs status', Jobs::StatusCommand
  end
end

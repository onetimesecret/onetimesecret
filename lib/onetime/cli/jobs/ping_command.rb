# lib/onetime/cli/jobs/ping_command.rb
#
# frozen_string_literal: true

#
# CLI command for testing job queue communication
#
# Usage:
#   ots jobs ping [options]
#
# Options:
#   -q, --queue QUEUE    Test specific queue only (email, billing, notification, transient)
#   -w, --wait SECONDS   Wait for worker response (default: 5)
#   -n, --dry-run        Show what would be published without sending
#
# This command publishes test messages to verify workers receive them correctly.
# Run with a worker in another terminal: bin/ots jobs worker
#

require 'bunny'
require 'securerandom'
require_relative '../../jobs/queue_config'

module Onetime
  module CLI
    module Jobs
      class PingCommand < Command
        desc 'Test job queue communication by sending ping messages'

        option :queue, type: :string, aliases: ['q'],
          desc: 'Test specific queue: email, billing, notification, transient (default: all)'
        option :wait, type: :integer, default: 5, aliases: ['w'],
          desc: 'Seconds to wait for worker acknowledgment'
        option :dry_run, type: :boolean, default: false, aliases: ['n'],
          desc: 'Show what would be published without sending'

        # Map friendly names to actual queue names
        QUEUE_MAP = {
          'email' => 'email.message.send',
          'billing' => 'billing.event.process',
          'notification' => 'notifications.alert.push',
          'transient' => 'system.transient',
        }.freeze

        def call(queue: nil, wait: 5, dry_run: false, **)
          boot_application!

          queues_to_test = if queue
            unless QUEUE_MAP.key?(queue)
              puts "Unknown queue: #{queue}"
              puts "Available: #{QUEUE_MAP.keys.join(', ')}"
              exit 1
            end
            [QUEUE_MAP[queue]]
          else
            QUEUE_MAP.values
          end

          if dry_run
            puts 'DRY RUN - would ping these queues:'
            queues_to_test.each { |q| puts "  - #{q}" }
            return
          end

          ping_queues(queues_to_test, wait)
        end

        private

        def ping_queues(queue_names, wait_seconds)
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')

          bunny_config = {
            logger: Onetime.get_logger('Bunny'),
          }
          bunny_config.merge!(Onetime::Jobs::QueueConfig.tls_options(amqp_url))

          conn = Bunny.new(amqp_url, **bunny_config)
          conn.start
          channel = conn.create_channel

          puts '═' * 60
          puts 'Job Queue Ping Test'
          puts '═' * 60
          puts
          puts "RabbitMQ: #{amqp_url.gsub(/:[^:@]+@/, ':***@')}"
          puts "Wait time: #{wait_seconds}s"
          puts

          results = {}

          queue_names.each do |queue_name|
            result = ping_queue(channel, queue_name, wait_seconds)
            results[queue_name] = result
            display_result(queue_name, result)
          end

          conn.close

          puts
          puts '═' * 60
          puts 'Summary'
          puts '═' * 60

          success_count = results.count { |_, r| r[:published] }
          puts "Published: #{success_count}/#{results.size}"
          puts
          puts 'Workers should log messages like:'
          puts '  [Worker] Processing ping: test_ping_<timestamp>'
          puts
          puts 'Check worker logs to verify receipt.'
        end

        def ping_queue(channel, queue_name, wait_seconds)
          ping_id = "test_ping_#{Time.now.to_i}_#{SecureRandom.hex(4)}"
          message = build_test_message(queue_name, ping_id)

          # Ensure queue exists (passive check)
          begin
            channel.queue(queue_name, passive: true)
          rescue Bunny::NotFound
            return { published: false, error: 'Queue not found - run: bin/ots jobs reset-queues' }
          end

          # Publish the test message
          channel.default_exchange.publish(
            message.to_json,
            routing_key: queue_name,
            persistent: true,
            message_id: ping_id,
            headers: {
              'x-schema-version' => Onetime::Jobs::QueueConfig::CURRENT_SCHEMA_VERSION,
              'x-ping-test' => true,
            },
          )

          { published: true, ping_id: ping_id, message: message }
        rescue StandardError => ex
          { published: false, error: ex.message }
        end

        def build_test_message(queue_name, ping_id)
          case queue_name
          when 'email.message.send'
            # Test message that EmailWorker will recognize but not actually send
            {
              template: :ping_test,
              data: {
                ping_id: ping_id,
                timestamp: Time.now.utc.iso8601,
                test: true,
              },
            }
          when 'billing.event.process'
            # Test message for BillingWorker
            {
              event_id: ping_id,
              event_type: 'ping.test',
              payload: { test: true }.to_json,
              received_at: Time.now.utc.iso8601,
            }
          when 'notifications.alert.push'
            # Test message for NotificationWorker
            {
              type: 'ping.test',
              addressee: { custid: 'test', email: 'test@example.com' },
              template: 'ping_test',
              locale: 'en',
              channels: [],
              data: { ping_id: ping_id, timestamp: Time.now.utc.iso8601 },
            }
          when 'system.transient'
            # Test message for TransientWorker
            {
              action: 'ping',
              ping_id: ping_id,
              timestamp: Time.now.utc.iso8601,
            }
          else
            { ping_id: ping_id, timestamp: Time.now.utc.iso8601 }
          end
        end

        def display_result(queue_name, result)
          if result[:published]
            puts "#{queue_name}"
            puts "  Status: Published"
            puts "  Ping ID: #{result[:ping_id]}"
          else
            puts "#{queue_name}"
            puts "  Status: FAILED"
            puts "  Error: #{result[:error]}"
          end
          puts
        end
      end
    end

    register 'jobs ping', Jobs::PingCommand
  end
end

# lib/onetime/cli/queue/dlq_command.rb
#
# frozen_string_literal: true

#
# CLI commands for managing Dead Letter Queues (DLQs)
#
# Usage:
#   ots queue dlq list [queue-name]     List DLQ messages
#   ots queue dlq show <queue> --id ID  Show specific message details
#   ots queue dlq replay <queue>        Replay messages back to original queue
#   ots queue dlq purge <queue>         Remove messages from DLQ
#

require 'bunny'
require 'json'
require_relative '../../jobs/queue_config'

module Onetime
  module CLI
    module Queue
      # Base class with shared DLQ functionality
      class DlqBase < Command
        private

        # Map short queue names to full DLQ queue names
        # Accepts: "billing.event", "dlq.billing.event", or full name
        def resolve_dlq_name(name)
          return name if name.start_with?('dlq.')

          dlq_name = "dlq.#{name}"
          unless valid_dlq?(dlq_name)
            valid_names = Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.values.map { |v| v[:queue] }
            puts "Unknown DLQ: #{name}"
            puts "Available DLQs: #{valid_names.map { |n| n.sub('dlq.', '') }.join(', ')}"
            exit 1
          end
          dlq_name
        end

        def valid_dlq?(dlq_name)
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.values.any? { |v| v[:queue] == dlq_name }
        end

        def all_dlq_names
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.values.map { |v| v[:queue] }
        end

        def with_rabbitmq_connection
          url  = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          conn = Bunny.new(url)
          conn.start
          yield conn
        ensure
          conn&.close
        end

        def format_age(timestamp)
          return 'unknown' unless timestamp

          age_seconds = Time.now.to_i - timestamp.to_i
          case age_seconds
          when 0..59 then "#{age_seconds}s ago"
          when 60..3599 then "#{age_seconds / 60}m ago"
          when 3600..86_399 then "#{age_seconds / 3600}h ago"
          else "#{age_seconds / 86_400}d ago"
          end
        end
      end

      # List DLQ messages
      class DlqListCommand < DlqBase
        desc 'List messages in Dead Letter Queues'

        argument :queue, type: :string, required: false,
          desc: 'Specific DLQ to list (e.g., billing.event)'
        option :format, type: :string, default: 'text', aliases: ['f'],
          desc: 'Output format: text or json'
        option :limit, type: :integer, default: 20, aliases: ['n'],
          desc: 'Maximum messages to show per queue'

        def call(queue: nil, format: 'text', limit: 20, **)
          boot_application!

          if queue
            list_queue_messages(resolve_dlq_name(queue), format, limit)
          else
            list_all_dlqs(format)
          end
        end

        private

        def list_all_dlqs(format)
          with_rabbitmq_connection do |conn|
            channel = conn.create_channel
            summary = []

            all_dlq_names.each do |dlq_name|
              info = get_queue_info(channel, dlq_name)
              summary << info
            rescue Bunny::NotFound
              summary << { queue: dlq_name, messages: 0, error: 'not declared' }
              channel = conn.create_channel
            end

            if format == 'json'
              puts JSON.pretty_generate(summary)
            else
              display_summary_text(summary)
            end
          end
        rescue StandardError => ex
          puts "Error connecting to RabbitMQ: #{ex.message}"
          exit 1
        end

        def get_queue_info(channel, dlq_name)
          queue = channel.queue(dlq_name, durable: true, passive: true)
          {
            queue: dlq_name,
            messages: queue.message_count,
            consumers: queue.consumer_count,
          }
        end

        def display_summary_text(summary)
          puts '═' * 70
          puts 'Dead Letter Queue Summary'
          puts '═' * 70
          puts
          puts format('%-30s %10s %10s', 'Queue', 'Messages', 'Consumers')
          puts '-' * 70

          total = 0
          summary.each do |info|
            if info[:error]
              puts format('%-30s %10s', info[:queue], info[:error])
            else
              puts format('%-30s %10d %10d', info[:queue], info[:messages], info[:consumers])
              total += info[:messages]
            end
          end

          puts '-' * 70
          puts format('%-30s %10d', 'Total', total)
          puts
        end

        def list_queue_messages(dlq_name, format, limit)
          with_rabbitmq_connection do |conn|
            channel = conn.create_channel
            queue   = channel.queue(dlq_name, durable: true, passive: true)

            message_count = queue.message_count
            if message_count == 0
              puts "No messages in #{dlq_name}"
              return
            end

            messages = peek_messages(channel, dlq_name, [limit, message_count].min)

            if format == 'json'
              puts JSON.pretty_generate({
                queue: dlq_name,
                total_messages: message_count,
                showing: messages.size,
                messages: messages,
              },
                                       )
            else
              display_messages_text(dlq_name, message_count, messages)
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
        rescue StandardError => ex
          puts "Error: #{ex.message}"
          exit 1
        end

        def peek_messages(channel, dlq_name, count)
          messages = []
          queue    = channel.queue(dlq_name, durable: true, passive: true)

          count.times do
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            begin
              death_info = extract_death_info(properties.headers)
              messages << {
                delivery_tag: delivery_info.delivery_tag,
                message_id: properties.message_id,
                timestamp: properties.timestamp&.to_i,
                age: format_age(properties.timestamp),
                original_queue: death_info[:queue],
                death_reason: death_info[:reason],
                death_count: death_info[:count],
                error: death_info[:error],
                content_type: properties.content_type,
                payload_preview: payload.to_s[0..200],
              }
            ensure
              # Always nack with requeue to return message to queue
              channel.nack(delivery_info.delivery_tag, false, true)
            end
          end

          messages
        end

        def extract_death_info(headers)
          return {} unless headers

          death = headers['x-death']&.first || {}
          {
            queue: death['queue'],
            reason: death['reason'],
            count: death['count'],
            error: headers['x-exception'] || headers['x-error'],
          }
        end

        def display_messages_text(dlq_name, total, messages)
          puts '═' * 70
          puts "Dead Letter Queue: #{dlq_name}"
          puts "Total messages: #{total}, showing: #{messages.size}"
          puts '═' * 70
          puts

          messages.each_with_index do |msg, idx|
            puts format('[%d] Message ID: %s', idx + 1, msg[:message_id] || 'N/A')
            puts format('    Age: %s | Original Queue: %s', msg[:age], msg[:original_queue] || 'unknown')
            puts format('    Death Reason: %s | Death Count: %d', msg[:death_reason] || 'unknown', msg[:death_count] || 0)
            puts format('    Error: %s', msg[:error]) if msg[:error]
            puts format('    Payload: %s...', msg[:payload_preview][0..80]) if msg[:payload_preview]
            puts
          end
        end
      end

      # Show details of a specific DLQ message
      class DlqShowCommand < DlqBase
        desc 'Show details of a specific DLQ message'

        argument :queue, type: :string, required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :id, type: :string, aliases: ['i'],
          desc: 'Message ID to show'
        option :index, type: :integer, aliases: ['n'],
          desc: 'Message index (1-based) to show'
        option :format, type: :string, default: 'text', aliases: ['f'],
          desc: 'Output format: text or json'

        def call(queue:, id: nil, index: nil, format: 'text', **)
          boot_application!

          unless id || index
            puts 'Error: Must specify --id or --index'
            exit 1
          end

          dlq_name = resolve_dlq_name(queue)
          show_message(dlq_name, id, index, format)
        end

        private

        def show_message(dlq_name, message_id, index, format)
          with_rabbitmq_connection do |conn|
            channel = conn.create_channel
            queue   = channel.queue(dlq_name, durable: true, passive: true)

            if queue.message_count == 0
              puts "No messages in #{dlq_name}"
              return
            end

            message = find_message(channel, dlq_name, message_id, index, queue.message_count)

            if message.nil?
              puts message_id ? "Message not found: #{message_id}" : "Message at index #{index} not found"
              exit 1
            end

            if format == 'json'
              puts JSON.pretty_generate(message)
            else
              display_message_detail(message)
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
        end

        def find_message(channel, dlq_name, message_id, index, total)
          queue   = channel.queue(dlq_name, durable: true, passive: true)
          found   = nil
          checked = []

          total.times do |i|
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            checked << delivery_info.delivery_tag
            match = if message_id
                      properties.message_id == message_id
                    else
                      (i + 1) == index
                    end

            if match
              found = build_message_detail(delivery_info, properties, payload)
            end

            # Requeue message
            channel.nack(delivery_info.delivery_tag, false, true)

            break if found
          end

          found
        end

        def build_message_detail(delivery_info, properties, payload)
          headers = properties.headers || {}
          death   = headers['x-death']&.first || {}

          {
            delivery_tag: delivery_info.delivery_tag,
            message_id: properties.message_id,
            timestamp: properties.timestamp&.iso8601,
            content_type: properties.content_type,
            headers: headers,
            death_info: {
              original_queue: death['queue'],
              original_exchange: death['exchange'],
              reason: death['reason'],
              count: death['count'],
              time: death['time']&.iso8601,
              routing_keys: death['routing-keys'],
            },
            payload: safe_parse_payload(payload, properties.content_type),
          }
        end

        def safe_parse_payload(payload, content_type)
          return payload unless content_type&.include?('json')

          JSON.parse(payload)
        rescue JSON::ParserError
          payload
        end

        def display_message_detail(msg)
          puts '═' * 70
          puts 'Message Details'
          puts '═' * 70
          puts
          puts format('Message ID:    %s', msg[:message_id] || 'N/A')
          puts format('Timestamp:     %s', msg[:timestamp] || 'N/A')
          puts format('Content-Type:  %s', msg[:content_type] || 'N/A')
          puts

          puts 'Death Info:'
          death = msg[:death_info]
          puts format('  Original Queue:    %s', death[:original_queue] || 'N/A')
          puts format('  Original Exchange: %s', death[:original_exchange] || 'N/A')
          puts format('  Reason:            %s', death[:reason] || 'N/A')
          puts format('  Death Count:       %d', death[:count] || 0)
          puts format('  Death Time:        %s', death[:time] || 'N/A')
          puts

          puts 'Headers:'
          msg[:headers].each do |k, v|
            next if k == 'x-death'

            puts format('  %s: %s', k, v.inspect)
          end
          puts

          puts 'Payload:'
          if msg[:payload].is_a?(Hash)
            puts JSON.pretty_generate(msg[:payload]).gsub(/^/, '  ')
          else
            puts "  #{msg[:payload]}"
          end
          puts
        end
      end

      # Replay DLQ messages back to original queue
      class DlqReplayCommand < DlqBase
        desc 'Replay messages from DLQ back to original queue'

        argument :queue, type: :string, required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :count, type: :integer, aliases: ['n'],
          desc: 'Number of messages to replay (default: all)'
        option :format, type: :string, default: 'text', aliases: ['f'],
          desc: 'Output format: text or json'

        def call(queue:, count: nil, format: 'text', **)
          boot_application!

          dlq_name = resolve_dlq_name(queue)
          replay_messages(dlq_name, count, format)
        end

        private

        def replay_messages(dlq_name, count, format)
          with_rabbitmq_connection do |conn|
            channel = conn.create_channel
            queue   = channel.queue(dlq_name, durable: true, passive: true)

            available = queue.message_count
            if available == 0
              puts "No messages in #{dlq_name}"
              return
            end

            to_replay = count ? [count, available].min : available
            results   = { replayed: 0, failed: 0, errors: [] }

            to_replay.times do
              delivery_info, properties, payload = queue.pop(manual_ack: true)
              break unless delivery_info

              original_queue = extract_original_queue(properties.headers)
              unless original_queue
                results[:failed] += 1
                results[:errors] << { message_id: properties.message_id, error: 'No original queue found' }
                # Nack without requeue - message stays in DLQ, prevents infinite loop
                channel.nack(delivery_info.delivery_tag, false, false)
                next
              end

              begin
                # Republish to original queue
                channel.default_exchange.publish(
                  payload,
                  routing_key: original_queue,
                  persistent: true,
                  message_id: properties.message_id,
                  content_type: properties.content_type,
                  headers: clean_headers(properties.headers),
                )

                # Acknowledge (remove from DLQ)
                channel.ack(delivery_info.delivery_tag)
                results[:replayed] += 1
              rescue StandardError => ex
                results[:failed] += 1
                results[:errors] << { message_id: properties.message_id, error: ex.message }
                channel.nack(delivery_info.delivery_tag, false, true)
              end
            end

            if format == 'json'
              puts JSON.pretty_generate(results)
            else
              display_replay_results(dlq_name, results)
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
        end

        def extract_original_queue(headers)
          return nil unless headers

          death = headers['x-death']&.first
          death&.fetch('queue', nil)
        end

        def clean_headers(headers)
          return {} unless headers

          # Remove death-related headers for clean replay
          headers.reject { |k, _| k.start_with?('x-death', 'x-first-death') }
        end

        def display_replay_results(dlq_name, results)
          puts '═' * 70
          puts "Replay Results: #{dlq_name}"
          puts '═' * 70
          puts
          puts format('Replayed: %d', results[:replayed])
          puts format('Failed:   %d', results[:failed])

          if results[:errors].any?
            puts
            puts 'Errors:'
            results[:errors].each do |err|
              puts format('  %s: %s', err[:message_id] || 'unknown', err[:error])
            end
          end
          puts
        end
      end

      # Purge messages from a DLQ
      class DlqPurgeCommand < DlqBase
        desc 'Purge (delete) messages from a Dead Letter Queue'

        argument :queue, type: :string, required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :force, type: :boolean, default: false, aliases: ['f'],
          desc: 'Skip confirmation prompt'
        option :format, type: :string, default: 'text',
          desc: 'Output format: text or json'

        def call(queue:, force: false, format: 'text', **)
          boot_application!

          dlq_name = resolve_dlq_name(queue)
          purge_queue(dlq_name, force, format)
        end

        private

        def purge_queue(dlq_name, force, format)
          with_rabbitmq_connection do |conn|
            channel = conn.create_channel
            queue   = channel.queue(dlq_name, durable: true, passive: true)

            count = queue.message_count
            if count == 0
              puts "No messages in #{dlq_name}"
              return
            end

            unless force
              puts "WARNING: This will permanently delete #{count} message(s) from #{dlq_name}"
              print 'Continue? [y/N] '
              response = $stdin.gets&.strip&.downcase
              unless response == 'y'
                puts 'Aborted.'
                exit 0
              end
            end

            queue.purge
            result = { queue: dlq_name, purged: count }

            if format == 'json'
              puts JSON.pretty_generate(result)
            else
              puts "Purged #{count} message(s) from #{dlq_name}"
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
        end
      end
    end

    # Register all DLQ subcommands
    register 'queue dlq list', Queue::DlqListCommand
    register 'queue dlq show', Queue::DlqShowCommand
    register 'queue dlq replay', Queue::DlqReplayCommand
    register 'queue dlq purge', Queue::DlqPurgeCommand

    # Aliases (queues → queue)
    register 'queues dlq list', Queue::DlqListCommand
    register 'queues dlq show', Queue::DlqShowCommand
    register 'queues dlq replay', Queue::DlqReplayCommand
    register 'queues dlq purge', Queue::DlqPurgeCommand
  end
end

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
# The DLQ list / show / replay / purge capability now lives in central operations
# (epic #42 / D3): the SINGLE implementation of each verb. These CLI commands are
# thin adapters over Onetime::Operations::Dlq::{List, Peek, Show, Replay, Purge}
# and Onetime::Operations::Dlq::Store, preserving the historic output byte-for-byte
# while the same ops now back the new colonel `/api/colonel/queues/dlq…` endpoints.
# Loaded explicitly because CLI runs don't go through an app autoloader.
#

require 'bunny'
require 'json'
require_relative '../../jobs/queues/config'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/list'
require 'onetime/operations/dlq/peek'
require 'onetime/operations/dlq/show'
require 'onetime/operations/dlq/replay'
require 'onetime/operations/dlq/purge'

module Onetime
  module CLI
    module Queue
      # Base class with shared DLQ functionality
      class DlqBase < Command
        # Audit actor sentinel for CLI-initiated mutations (matches the session /
        # banner CLI convention). The colonel endpoints pass the acting colonel's
        # PUBLIC extid instead.
        CLI_ACTOR = 'cli'

        # The single extracted DLQ store (name allowlist + message projections).
        Store = Onetime::Operations::Dlq::Store

        private

        # Map short queue names to full DLQ queue names
        # Accepts: "billing.event", "dlq.billing.event", or full name
        def resolve_dlq_name(name)
          return name if name.start_with?('dlq.')

          dlq_name = "dlq.#{name}"
          unless Store.valid?(dlq_name)
            puts "Unknown DLQ: #{name}"
            puts "Available DLQs: #{Store.short_names.join(', ')}"
            exit 1
          end
          dlq_name
        end

        def with_rabbitmq_connection
          url  = OT.conf.dig('jobs', 'rabbitmq_url')
          conn = Bunny.new(url)
          conn.start
          yield conn
        ensure
          conn&.close
        end
      end

      # List DLQ messages
      class DlqListCommand < DlqBase
        desc 'List messages in Dead Letter Queues'

        argument :queue,
          type: :string,
          required: false,
          desc: 'Specific DLQ to list (e.g., billing.event)'
        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'
        option :limit,
          type: :integer,
          default: 20,
          aliases: ['n'],
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
            summary = Onetime::Operations::Dlq::List.new(connection: conn).call.dlqs

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
            result = Onetime::Operations::Dlq::Peek.new(
              connection: conn, queue: dlq_name, limit: limit,
            ).call

            if result.total_messages == 0
              puts "No messages in #{dlq_name}"
              return
            end

            if format == 'json'
              puts JSON.pretty_generate(
                {
                  queue: dlq_name,
                  total_messages: result.total_messages,
                  showing: result.messages.size,
                  messages: result.messages,
                },
              )
            else
              display_messages_text(dlq_name, result.total_messages, result.messages)
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
        rescue StandardError => ex
          puts "Error: #{ex.message}"
          exit 1
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

        argument :queue,
          type: :string,
          required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :id,
          type: :string,
          aliases: ['i'],
          desc: 'Message ID to show'
        option :index,
          type: :integer,
          aliases: ['n'],
          desc: 'Message index (1-based) to show'
        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
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
            result = Onetime::Operations::Dlq::Show.new(
              connection: conn, queue: dlq_name, message_id: message_id, index: index,
            ).call

            if result.empty
              puts "No messages in #{dlq_name}"
              return
            end

            if result.message.nil?
              puts message_id ? "Message not found: #{message_id}" : "Message at index #{index} not found"
              exit 1
            end

            if format == 'json'
              puts JSON.pretty_generate(result.message)
            else
              display_message_detail(result.message)
            end
          end
        rescue Bunny::NotFound
          puts "Queue not found: #{dlq_name}"
          exit 1
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

        argument :queue,
          type: :string,
          required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :count,
          type: :integer,
          aliases: ['n'],
          desc: 'Number of messages to replay (default: all)'
        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: 'Output format: text or json'

        def call(queue:, count: nil, format: 'text', **)
          boot_application!

          dlq_name = resolve_dlq_name(queue)
          replay_messages(dlq_name, count, format)
        end

        private

        def replay_messages(dlq_name, count, format)
          with_rabbitmq_connection do |conn|
            result = Onetime::Operations::Dlq::Replay.new(
              connection: conn, queue: dlq_name, count: count, actor: CLI_ACTOR,
            ).call

            # Only the truly-empty queue prints "No messages"; a non-empty queue
            # that happened to process nothing still prints the results table
            # (:noop), preserving the historic CLI behaviour byte-for-byte.
            if result.status == :empty
              puts "No messages in #{dlq_name}"
              return
            end

            results = { replayed: result.replayed, failed: result.failed, errors: result.errors }

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

        argument :queue,
          type: :string,
          required: true,
          desc: 'DLQ name (e.g., billing.event)'
        option :force,
          type: :boolean,
          default: false,
          aliases: ['f'],
          desc: 'Skip confirmation prompt'
        option :format,
          type: :string,
          default: 'text',
          desc: 'Output format: text or json'

        def call(queue:, force: false, format: 'text', **)
          boot_application!

          dlq_name = resolve_dlq_name(queue)
          purge_queue(dlq_name, force, format)
        end

        private

        def purge_queue(dlq_name, force, format)
          with_rabbitmq_connection do |conn|
            # Dry-run first to get the in-scope count for the confirmation prompt
            # WITHOUT mutating anything (no audit event is recorded on a dry-run).
            count = Onetime::Operations::Dlq::Purge.new(
              connection: conn, queue: dlq_name, actor: CLI_ACTOR, dry_run: true,
            ).call.count

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

            # Live purge — the single audited implementation records exactly one
            # AdminAuditEvent for the (non-empty) purge.
            result = Onetime::Operations::Dlq::Purge.new(
              connection: conn, queue: dlq_name, actor: CLI_ACTOR,
            ).call

            if format == 'json'
              puts JSON.pretty_generate({ queue: dlq_name, purged: result.purged })
            else
              puts "Purged #{result.purged} message(s) from #{dlq_name}"
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

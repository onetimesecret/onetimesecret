# lib/onetime/cli/queue/reset_command.rb
#
# frozen_string_literal: true

#
# CLI command for resetting RabbitMQ queues
#
# Use when queue properties become mismatched (PRECONDITION_FAILED errors).
# This deletes and recreates queues with correct configuration.
#
# Usage:
#   ots queue reset [options]
#
# Options:
#   -q, --queue NAME       Reset specific queue only
#   -f, --force            Skip confirmation prompt
#   --dry-run              Show what would be deleted without doing it
#

require 'bunny'
require_relative '../../jobs/queues/config'
require_relative '../../jobs/queues/declarator'

module Onetime
  module CLI
    module Queue
      class ResetCommand < Command
        desc 'Reset RabbitMQ queues (WARNING: destroys pending messages)'

        option :queue,
          type: :string,
          aliases: ['q'],
          desc: 'Reset specific queue only'
        option :force,
          type: :boolean,
          default: false,
          aliases: ['f'],
          desc: 'Skip confirmation prompt'
        option :dry_run,
          type: :boolean,
          default: false,
          desc: 'Show what would be deleted without doing it'

        def call(queue: nil, force: false, dry_run: false, **)
          boot_application!

          all_queues      = Onetime::Jobs::QueueDeclarator.queue_names +
                            Onetime::Jobs::QueueDeclarator.dlq_names
          queues_to_reset = queue ? [queue] : all_queues

          # Validate queue names via QueueDeclarator
          queues_to_reset.each do |q|
            next if Onetime::Jobs::QueueDeclarator.known_queue?(q)

            puts "Unknown queue: #{q}"
            puts "Available queues: #{Onetime::Jobs::QueueDeclarator.queue_names.join(', ')}"
            exit 1
          end

          if dry_run
            puts 'DRY RUN - would reset these queues:'
            queues_to_reset.each { |q| puts "  - #{q}" }
            return
          end

          unless force
            puts 'This will DELETE and recreate the following queues:'
            queues_to_reset.each { |q| puts "  - #{q}" }
            puts
            puts 'Messages in these queues will be LOST.'
            print 'Continue? [y/N] '
            response = $stdin.gets&.strip&.downcase
            unless response == 'y'
              puts 'Aborted.'
              exit 0
            end
          end

          reset_queues(queues_to_reset)
        end

        private

        def reset_queues(queue_names)
          conn    = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start
          channel = conn.create_channel

          queue_names.each do |queue_name|
            # Try to delete existing queue
            begin
              # Use passive: true to check if queue exists without declaring
              channel.queue(queue_name, passive: true)
              channel.queue_delete(queue_name)
              puts "Deleted: #{queue_name}"
            rescue Bunny::NotFound
              puts "Not found (skipping delete): #{queue_name}"
              # Channel is closed after NotFound, need to reopen
              channel = conn.create_channel
            end

            # Recreate with correct configuration via QueueDeclarator
            dlq_names = Onetime::Jobs::QueueDeclarator.dlq_names
            if dlq_names.include?(queue_name)
              opts = Onetime::Jobs::QueueDeclarator.dlq_options_for(queue_name)
              channel.queue(queue_name, **opts)
            else
              opts = Onetime::Jobs::QueueDeclarator.queue_options_for(queue_name)
              Onetime::Jobs::QueueDeclarator.declare_queue(channel, queue_name)
            end
            puts "Created: #{queue_name} (durable: #{opts[:durable]}, arguments: #{opts[:arguments]})"
          end

          conn.close
          puts
          puts 'Done. Queues reset with configuration from QueueDeclarator.'
        rescue StandardError => ex
          puts "Error: #{ex.message}"
          exit 1
        end
      end
    end

    register 'queue reset', Queue::ResetCommand
    register 'queues reset', Queue::ResetCommand  # Alias
  end
end

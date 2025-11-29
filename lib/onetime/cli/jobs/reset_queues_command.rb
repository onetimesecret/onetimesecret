# lib/onetime/cli/jobs/reset_queues_command.rb
#
# frozen_string_literal: true

#
# CLI command for resetting RabbitMQ queues
#
# Use when queue properties become mismatched (PRECONDITION_FAILED errors).
# This deletes and recreates queues with correct configuration.
#
# Usage:
#   ots jobs reset-queues [options]
#
# Options:
#   -q, --queue NAME       Reset specific queue only
#   -f, --force            Skip confirmation prompt
#   --dry-run              Show what would be deleted without doing it
#

require 'bunny'
require_relative '../../jobs/queue_config'

module Onetime
  module CLI
    module Jobs
      class ResetQueuesCommand < Command
        desc 'Reset RabbitMQ queues (WARNING: destroys pending messages)'

        option :queue, type: :string, aliases: ['q'],
          desc: 'Reset specific queue only'
        option :force, type: :boolean, default: false, aliases: ['f'],
          desc: 'Skip confirmation prompt'
        option :dry_run, type: :boolean, default: false,
          desc: 'Show what would be deleted without doing it'

        def call(queue: nil, force: false, dry_run: false, **)
          boot_application!

          queues_to_reset = queue ? [queue] : Onetime::Jobs::QueueConfig::QUEUES.keys

          # Validate queue names
          queues_to_reset.each do |q|
            unless Onetime::Jobs::QueueConfig::QUEUES.key?(q)
              puts "Unknown queue: #{q}"
              puts "Available queues: #{Onetime::Jobs::QueueConfig::QUEUES.keys.join(', ')}"
              exit 1
            end
          end

          if dry_run
            puts "DRY RUN - would reset these queues:"
            queues_to_reset.each { |q| puts "  - #{q}" }
            return
          end

          unless force
            puts "This will DELETE and recreate the following queues:"
            queues_to_reset.each { |q| puts "  - #{q}" }
            puts
            puts "Messages in these queues will be LOST."
            print "Continue? [y/N] "
            response = $stdin.gets&.strip&.downcase
            unless response == 'y'
              puts "Aborted."
              exit 0
            end
          end

          reset_queues(queues_to_reset)
        end

        private

        def reset_queues(queue_names)
          conn = Bunny.new(ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672'))
          conn.start
          channel = conn.create_channel

          queue_names.each do |queue_name|
            config = Onetime::Jobs::QueueConfig::QUEUES[queue_name]

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

            # Recreate with correct configuration
            channel.queue(
              queue_name,
              durable: config[:durable],
              arguments: config[:arguments] || {}
            )
            puts "Created: #{queue_name} (durable: #{config[:durable]}, arguments: #{config[:arguments] || {}})"
          end

          conn.close
          puts
          puts "Done. Queues reset with configuration from QueueConfig."
        rescue StandardError => e
          puts "Error: #{e.message}"
          exit 1
        end
      end
    end

    register 'jobs reset-queues', Jobs::ResetQueuesCommand
  end
end

# lib/onetime/cli_v2/migrate_redis_data_command.rb
#
# frozen_string_literal: true

require_relative '../cli/migrate_redis_data_command'

module Onetime
  module CLI
    module V2
      class MigrateRedisDataCommand < Dry::CLI::Command
        desc 'Consolidate Redis data from multiple databases to database 0'

        option :run, type: :boolean, default: false, aliases: ['r'], desc: 'Execute the consolidation (required for actual operation)'
        option :show_commands, type: :boolean, default: false, aliases: ['s'], desc: 'Generate redis-cli commands for manual execution'
        option :yes, type: :boolean, default: false, aliases: ['y'], desc: 'Auto-confirm consolidation (non-interactive mode)'
        option :batch_size, type: :integer, default: 100, aliases: ['b'], desc: 'Set batch size for consolidation (max: 10000)'
        option :help, type: :boolean, default: false, aliases: ['h'], desc: 'Show detailed help message'

        def call(run: false, show_commands: false, yes: false, batch_size: 100, help: false, **)
          # Create a mock drydock object that mimics the old interface
          mock_obj = Struct.new(:option).new(
            Struct.new(:run, :show_commands, :yes, :batch_size, :help).new(
              run, show_commands, yes, batch_size, help
            )
          )

          # Set environment variable to bypass startup warnings
          ENV['SKIP_LEGACY_DATA_CHECK'] = 'true'

          # Boot the application
          OT.boot! :cli

          # Create an instance of the original command and call it
          cmd = Onetime::MigrateRedisDataCommand.new
          cmd.init
          cmd.migrate_redis_data
        end
      end

      # Register the command
      register 'migrate-redis-data', MigrateRedisDataCommand
    end
  end
end

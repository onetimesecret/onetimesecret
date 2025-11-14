# lib/onetime/cli_v2/sync_auth_accounts_command.rb
#
# frozen_string_literal: true

require_relative '../cli/sync_auth_accounts_command'

module Onetime
  module CLI
    module V2
      class SyncAuthAccountsCommand < Dry::CLI::Command
        desc 'Synchronize customer records from Redis to Auth SQL database'

        option :run, type: :boolean, default: false, aliases: ['r'], desc: 'Execute synchronization (required for actual operation)'
        option :help, type: :boolean, default: false, aliases: ['h'], desc: 'Show detailed help message'

        def call(run: false, help: false, **)
          # Boot the application
          OT.boot! :cli

          # Create an instance of the original command
          # Note: The original command uses show_usage_help which checks obj.option.help
          # We'll need to simulate that interface
          cmd = Onetime::SyncAuthAccountsCommand.new

          # Monkey-patch the instance to respond to option accessors
          cmd.instance_variable_set(:@option, Struct.new(:run, :help).new(run, help))
          def cmd.option; @option; end

          cmd.init
          cmd.sync_auth_accounts
        end
      end

      # Register the command
      register 'sync-auth-accounts', SyncAuthAccountsCommand
    end
  end
end

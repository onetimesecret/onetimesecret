# lib/onetime/cli_v2/session_command.rb
#
# frozen_string_literal: true

require_relative '../cli/session_command'

module Onetime
  module CLI
    module V2
      class SessionCommand < Dry::CLI::Command
        desc 'Session inspection and debugging tools'

        argument :subcommand, type: :string, required: false, desc: 'Subcommand (inspect, list, search, delete, clean)'
        argument :arg1, type: :string, required: false, desc: 'Session ID, email, or custid depending on subcommand'

        option :limit, type: :integer, aliases: ['l'], desc: 'Limit number of results'
        option :force, type: :boolean, default: false, aliases: ['f'], desc: 'Force operation without confirmation'

        def call(subcommand: nil, arg1: nil, limit: nil, force: false, **)
          # Boot the application
          OT.boot! :cli

          # Build argv array
          argv = []
          argv << subcommand if subcommand
          argv << arg1 if arg1

          # Create mock drydock interface
          cmd = Onetime::SessionCommand.new
          cmd.instance_variable_set(:@argv, argv)
          cmd.instance_variable_set(:@option, Struct.new(:limit, :force).new(limit, force))

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.session
        end
      end

      # Register the command
      register 'session', SessionCommand
    end
  end
end

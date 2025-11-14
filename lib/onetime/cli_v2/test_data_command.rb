# lib/onetime/cli_v2/test_data_command.rb
#
# frozen_string_literal: true

require_relative '../cli/test_data_command'

module Onetime
  module CLI
    module V2
      class TestDataCommand < Dry::CLI::Command
        desc 'Create test organizations and teams for UI testing'

        argument :email, type: :string, required: true, desc: 'Customer email address'

        option :org_name, type: :string, aliases: ['o'], desc: 'Organization name (auto-generated if not provided)'
        option :team_name, type: :string, aliases: ['t'], desc: 'Team name (auto-generated if not provided)'
        option :cleanup, type: :boolean, default: false, aliases: ['c'], desc: 'Remove all non-default organizations and teams for the user'

        def call(email:, org_name: nil, team_name: nil, cleanup: false, **)
          # Boot the application
          OT.boot! :cli

          # Create mock drydock interface
          cmd = Onetime::TestDataCommand.new
          cmd.instance_variable_set(:@argv, [email])
          cmd.instance_variable_set(:@option, Struct.new(:org_name, :team_name, :cleanup).new(org_name, team_name, cleanup))

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.test_data
        end
      end

      # Register the command
      register 'test-data', TestDataCommand
    end
  end
end

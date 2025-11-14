# lib/onetime/cli_v2/change_email_command.rb
#
# frozen_string_literal: true

require_relative '../cli/change_email_command'

module Onetime
  module CLI
    module V2
      # Change email command
      class ChangeEmailCommandMain < Dry::CLI::Command
        desc 'Change customer email address and update all related records'

        argument :old_email, type: :string, required: true, desc: 'Current email address of the customer'
        argument :new_email, type: :string, required: true, desc: 'New email address to change to'
        argument :realm, type: :string, required: false, default: 'US', desc: 'Geographic region (US/EU/CA/NZ)'

        def call(old_email:, new_email:, realm: 'US', **)
          # Boot the application
          OT.boot! :cli

          # Build argv array
          argv = [old_email, new_email, realm].compact

          # Create mock drydock interface
          cmd = Onetime::ChangeEmailCommand.new
          cmd.instance_variable_set(:@argv, argv)
          cmd.instance_variable_set(:@option, Struct.new(:verbose).new(false))

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.change_email
        end
      end

      # Change email log command
      class ChangeEmailLogCommand < Dry::CLI::Command
        desc 'View history of email address changes'

        argument :email, type: :string, required: false, desc: 'Filter by email address'

        option :verbose, type: :boolean, default: false, aliases: ['v'], desc: 'Display full change reports'
        option :limit, type: :integer, default: 10, aliases: ['n'], desc: 'Limit number of reports to show'

        def call(email: nil, verbose: false, limit: 10, **)
          # Boot the application
          OT.boot! :cli

          # Build argv array
          argv = []
          argv << email if email

          # Create mock drydock interface
          cmd = Onetime::ChangeEmailCommand.new
          cmd.instance_variable_set(:@argv, argv)
          cmd.instance_variable_set(:@option, Struct.new(:verbose, :limit).new(verbose, limit))

          def cmd.argv; @argv; end
          def cmd.option; @option; end

          cmd.init
          cmd.change_email_log
        end
      end

      # Register the commands
      register 'change-email', ChangeEmailCommandMain
      register 'change-email-log', ChangeEmailLogCommand
    end
  end
end

# lib/onetime/cli_v2/customers_command.rb
#
# frozen_string_literal: true

require_relative '../cli/customers_command'

module Onetime
  module CLI
    module V2
      class CustomersCommand < Dry::CLI::Command
        desc 'Customer management tools'

        option :list, type: :boolean, default: false, aliases: ['l'], desc: 'List customer domains (by count)'
        option :check, type: :boolean, default: false, aliases: ['c'], desc: 'Show customer records where custid and email do not match (obscured)'

        def call(list: false, check: false, **)
          # Boot the application
          OT.boot! :cli

          # Create mock drydock interface
          cmd = Onetime::CustomersCommand.new
          cmd.instance_variable_set(:@option, Struct.new(:list, :check).new(list, check))
          def cmd.option; @option; end

          cmd.init
          cmd.customers
        end
      end

      # Register the command
      register 'customers', CustomersCommand
    end
  end
end

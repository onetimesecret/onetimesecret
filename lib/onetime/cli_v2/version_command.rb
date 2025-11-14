# lib/onetime/cli_v2/version_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    module V2
      class VersionCommand < DelayBootCommand
        desc 'Display version information'

        def call(**)
          puts format('Onetime %s', OT::VERSION.inspect)
        end
      end

      # Register the command
      register 'version', VersionCommand
      register 'build', VersionCommand  # Alias
    end
  end
end

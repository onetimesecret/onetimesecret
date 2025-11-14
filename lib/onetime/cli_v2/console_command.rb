# lib/onetime/cli_v2/console_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    module V2
      class ConsoleCommand < DelayBootCommand
        desc 'Ruby irb with Onetime preloaded'

        option :delay_boot, type: :boolean, default: false, aliases: ['B'], desc: 'Bring up the console without initializing'

        def call(delay_boot: false, **)
          cmd = format('irb -I%s -ronetime/console', File.join(Onetime::HOME, 'lib'))
          OT.ld cmd

          # Set the boot env var for the console process
          ENV['DELAY_BOOT'] = delay_boot.to_s
          Kernel.exec(cmd)
        end
      end

      # Register the command
      register 'console', ConsoleCommand
    end
  end
end

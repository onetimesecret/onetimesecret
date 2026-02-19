# lib/onetime/cli/install_command.rb
#
# frozen_string_literal: true

#
# CLI commands for tracking install.sh lifecycle
#
# Usage:
#   bin/ots install mark     Increment the init counter (call after init completes)
#   bin/ots install check    Exit 0 if initialized (counter > 0), 1 if not
#

module Onetime
  module CLI
    module Install
      COUNTER_KEY = 'onetime:install:init_count'

      class MarkCommand < Command
        desc 'Record that install.sh init has completed (increments counter)'

        def call(**)
          boot_application!
          count = Familia::Counter.new(COUNTER_KEY).increment
          puts count
        end
      end

      class CheckCommand < Command
        desc 'Exit 0 if environment has been initialized, 1 otherwise'

        def call(**)
          boot_application!
          count = Familia::Counter.new(COUNTER_KEY).value.to_i
          exit(count > 0 ? 0 : 1)
        rescue StandardError
          exit 1
        end
      end
    end

    register 'install mark', Install::MarkCommand
    register 'install check', Install::CheckCommand
  end
end

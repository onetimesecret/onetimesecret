# lib/onetime/cli_v2/load_path_command.rb
#
# frozen_string_literal: true

module Onetime
  module CLI
    module V2
      class LoadPathCommand < DelayBootCommand
        desc 'Lists the first 5 paths in the load path'

        def call(**)
          puts $LOAD_PATH[0...5]
        end
      end

      # Register the command
      register 'load-path', LoadPathCommand
    end
  end
end

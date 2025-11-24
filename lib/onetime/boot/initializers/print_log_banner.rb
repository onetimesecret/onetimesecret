# lib/onetime/boot/initializers/print_log_banner.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Print application boot banner
      class PrintLogBanner < Onetime::Boot::Initializer
        @depends_on = [:logging]
        @provides = [:banner_printed]
        @optional = true

        def execute(_context)
          # Only print in TTY mode, not in test/cli
          if $stdout.tty? && !Onetime.mode?(:test) && !Onetime.mode?(:cli)
            Onetime.print_log_banner
          end
        end
      end
    end
  end
end

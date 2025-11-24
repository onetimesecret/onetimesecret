# lib/onetime/boot/initializers/setup_loggers.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Initialize logging system
      #
      # Sets up SemanticLogger and application loggers.
      # Provides :logging capability.
      class SetupLoggers < Onetime::Boot::Initializer
        @provides = [:logging]

        def execute(_context)
          Onetime.setup_loggers
        end
      end
    end
  end
end

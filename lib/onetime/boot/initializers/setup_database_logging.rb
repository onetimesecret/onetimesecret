# lib/onetime/boot/initializers/setup_database_logging.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Configure database query logging
      class SetupDatabaseLogging < Onetime::Boot::Initializer
        @depends_on = [:logging]
        @provides = [:database_logging]

        def execute(_context)
          Onetime.setup_database_logging
        end
      end
    end
  end
end

# lib/onetime/boot/initializers/setup_connection_pool.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Initialize Redis connection pool
      class SetupConnectionPool < Onetime::Boot::Initializer
        @depends_on = [:legacy_check]
        @provides = [:database]

        def execute(_context)
          Onetime.setup_connection_pool
        end
      end
    end
  end
end

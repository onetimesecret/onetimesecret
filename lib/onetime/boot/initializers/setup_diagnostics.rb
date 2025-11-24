# lib/onetime/boot/initializers/setup_diagnostics.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Initialize diagnostics and monitoring
      #
      # Sets up Sentry and other diagnostics services.
      # Optional - can fail without halting boot.
      class SetupDiagnostics < Onetime::Boot::Initializer
        @depends_on = [:logging]
        @provides = [:diagnostics]
        @optional = true

        def execute(_context)
          Onetime.setup_diagnostics
        end
      end
    end
  end
end

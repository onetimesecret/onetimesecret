# lib/onetime/boot/initializers/configure_familia.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Configure Familia Redis ORM
      class ConfigureFamilia < Onetime::Boot::Initializer
        @depends_on = [:logging]
        @provides = [:familia_config]

        def execute(_context)
          Onetime.configure_familia
        end
      end
    end
  end
end

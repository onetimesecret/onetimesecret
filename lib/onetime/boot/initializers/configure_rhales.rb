# lib/onetime/boot/initializers/configure_rhales.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      class UconfigureUrhales  < Onetime::Boot::Initializer
        @provides = [:configure_rhales]

        def execute(_context)
          Onetime.configure_rhales
        end
      end
    end
  end
end

# lib/onetime/boot/initializers/load_fortunes.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      class UloadUfortunes  < Onetime::Boot::Initializer
        @provides = [:load_fortunes]

        def execute(_context)
          Onetime.load_fortunes
        end
      end
    end
  end
end

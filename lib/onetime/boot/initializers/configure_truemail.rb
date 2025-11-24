# lib/onetime/boot/initializers/configure_truemail.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      class UconfigureUtruemail  < Onetime::Boot::Initializer
        @provides = [:configure_truemail]

        def execute(_context)
          Onetime.configure_truemail
        end
      end
    end
  end
end

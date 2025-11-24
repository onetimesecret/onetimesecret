# lib/onetime/boot/initializers/check_global_banner.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Check for global banner message
      class CheckGlobalBanner < Onetime::Boot::Initializer
        @depends_on = [:database]
        @provides = [:banner]
        @optional = true

        def execute(_context)
          Onetime.check_global_banner
        end
      end
    end
  end
end

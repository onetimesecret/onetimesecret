# lib/onetime/boot/initializers/configure_domains.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Configure custom domains
      class ConfigureDomains < Onetime::Boot::Initializer
        @provides = [:domains]

        def execute(_context)
          Onetime.configure_domains
        end
      end
    end
  end
end

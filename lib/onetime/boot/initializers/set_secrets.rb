# lib/onetime/boot/initializers/set_secrets.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Configure application secrets
      class SetSecrets < Onetime::Boot::Initializer
        @provides = [:secrets]

        def execute(_context)
          Onetime.set_secrets
        end
      end
    end
  end
end

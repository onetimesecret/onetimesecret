# lib/onetime/boot/initializers/load_locales.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Load i18n locale files
      #
      # Provides :i18n capability for other initializers that need
      # translation support.
      class LoadLocales < Onetime::Boot::Initializer
        @provides = [:i18n]

        def execute(_context)
          Onetime.load_locales
        end
      end
    end
  end
end

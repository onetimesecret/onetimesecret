# lib/onetime/boot/initializers/detect_legacy_data_and_warn.rb
#
# frozen_string_literal: true

module Onetime
  module Boot
    module Initializers
      # Detect and warn about legacy data in Redis
      class DetectLegacyDataAndWarn < Onetime::Boot::Initializer
        @depends_on = [:familia_config]
        @provides = [:legacy_check]

        def execute(_context)
          Onetime.detect_legacy_data_and_warn
        end
      end
    end
  end
end

# lib/onetime/initializers/load_fortunes.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # LoadFortunes initializer
    #
    # Loads fortune messages from etc/fortunes file for display throughout
    # the application (e.g., footer messages, loading screens).
    #
    # Runtime state set:
    # - Onetime::Runtime.features.fortunes
    #
    class LoadFortunes < Onetime::Boot::Initializer
      def execute(_context)
        filepath = File.join(Onetime::HOME, 'etc', 'fortunes')

        fortunes_list = if File.exist?(filepath)
                          OT.ld "[init] Loading fortunes from #{filepath}"
                          File.readlines(filepath).map(&:strip).reject(&:empty?)
                        else
                          OT.ld "[init] Fortunes file not found: #{filepath}"
                          []
                        end

        # Update features runtime state with fortunes
        Onetime::Runtime.update_features(fortunes: fortunes_list)
      end
    end
  end
end

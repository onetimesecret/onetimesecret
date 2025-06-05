# lib/onetime/initializers/load_fortunes.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module LoadFortunes

      using IndifferentHashAccess

      def self.run(options = {})
        OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
        OT.ld "[initializer] Fortunes loaded (#{OT::Utils.fortunes.length} entries)"
      end

    end
  end
end

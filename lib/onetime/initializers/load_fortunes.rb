# lib/onetime/initializers/load_fortunes.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers

    using IndifferentHashAccess

    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end
  end
end

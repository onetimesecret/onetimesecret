# lib/onetime/initializers/load_fortunes.rb
# lib/onetime/initializers/load_fortunes.rb
module Onetime
  module Initializers
    def load_fortunes
      OT::Utils.fortunes ||= File.readlines(File.join(Onetime::HOME, 'etc', 'fortunes'))
    end
  end
end

# lib/onetime/initializers/load_fortunes.rb
# lib/onetime/initializers/load_fortunes.rb
module Onetime
  module Initializers
    def load_fortunes
      filepath = File.join(Onetime::HOME, 'etc', 'fortunes')
      OT.ld "[init] Loading fortunes from #{filepath}"
      OT::Utils.fortunes ||= File.readlines(filepath)
    end
  end
end

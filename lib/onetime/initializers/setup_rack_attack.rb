# lib/onetime/initializers/setup_rack_attack.rb


module Onetime
  module Initializers

    def setup_rack_attack
      require_relative '../../../etc/init.d/rack_attack'
    end
  end
end

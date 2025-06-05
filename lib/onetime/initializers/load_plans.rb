# lib/onetime/initializers/load_plans.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module LoadPlans

      using IndifferentHashAccess

      def self.run(options = {})
        OT::Plan.load_plans!
        OT.ld "[initializer] Plans loaded"
      end

    end
  end
end

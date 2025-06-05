# lib/onetime/initializers/load_plans.rb

require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers

    using IndifferentHashAccess

    def load_plans
      OT::Plan.load_plans!
    end
  end
end

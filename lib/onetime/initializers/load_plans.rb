# /Users/d/Projects/opensource/onetime/onetimesecret/lib/onetime/initializers/load_plans.rb
# lib/onetime/initializers/load_plans.rb
module Onetime
  module Initializers
    def load_plans
      OT::Plan.load_plans!
    end
  end
end

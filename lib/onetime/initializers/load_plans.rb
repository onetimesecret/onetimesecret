# lib/onetime/initializers/load_plans.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    def load_plans
      OT::Plan.load_plans!
    end
  end
end

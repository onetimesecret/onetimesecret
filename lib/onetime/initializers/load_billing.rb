# lib/onetime/initializers/load_billing.rb

module Onetime
  module Initializers
    def load_billing
      OT::Plan.load_billing
    end
  end
end

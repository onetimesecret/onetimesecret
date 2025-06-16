# lib/onetime/services/system/load_plans.rb

module Onetime
  module Initializers
    def load_plans
      OT::Plan.load_plans!
    end
  end
end

# NOTE: Moved from old lib/onetime/config.rb
# if config.dig('plans', 'enabled').to_s == 'true'
#   stripe_key = config.dig('plans', 'stripe_key')
#   unless stripe_key
#     raise OT::Problem, "No `site.plans.stripe_key` found in #{path}"
#   end

#   require 'stripe'
#   Stripe.api_key = stripe_key
# end

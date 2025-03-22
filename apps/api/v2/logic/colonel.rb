# apps/api/v2/logic/colonel.rb

require 'v1/logic/colonel'

require 'onetime/refinements/stripe_refinements'
require_relative 'base'

module V2::Logic
  module Colonel
    class GetColonel < V1::Logic::Colonel::GetColonel
    end
  end
end

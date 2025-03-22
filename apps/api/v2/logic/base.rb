# apps/api/v2/logic/base.rb

require 'stathat'
require 'timeout'

require 'onetime/refinements/rack_refinements'
require 'onetime/refinements/stripe_refinements'

require 'v1/logic'
require 'v1/models'

module V2
  module Logic
    class Base < V1::Logic::Base
      # We will want to have a @@customer_model set so that we can set it to
      # V2::Customer. Currently even if we're using the V2 of this logic,
      # it'll still be running with V1::Customer b/c that's what is
      # literally used V1::Logic::Base. A class variable is the way to
      # go so that all logic subclasses can see the thing.
    end

    extend V1::Logic::ClassMethods
  end
end

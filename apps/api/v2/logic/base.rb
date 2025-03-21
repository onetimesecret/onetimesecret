# apps/api/v2/logic/base.rb

require 'stathat'
require 'timeout'

require 'onetime/refinements/rack_refinements'
require 'v1/logic/base'

module V2
  module Logic
    class Base < V1::Logic::Base
    end

    extend V1::Logic::ClassMethods
  end
end

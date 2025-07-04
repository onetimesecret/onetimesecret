# apps/web/manifold/views.rb

require 'onetime/refinements/require_refinements'

require_relative 'views/base'

module Manifold
  module Views
    using Onetime::Ruequire

    ##
    # The VuePoint class serves as a bridge between the Ruby Rack application
    # and the Vue.js frontend. It is responsible for initializing and passing
    # JavaScript variables from the backend to the frontend.
    #
    # Example usage:
    #   view = Manifold::Views::VuePoint.new(req, sess, cust, locale)
    #
    class VuePoint < Manifold::Views::BaseView
      # No init method needed - uses BaseView constructor
    end

    class ExportWindow < Manifold::Views::BaseView
      # require 'views/example.rue'
      # No init method needed - uses BaseView constructor
    end

    class Error < Manifold::Views::BaseView
      def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {})
        # Add default title to business data
        error_data = { title: "I'm afraid there's been an error" }.merge(business_data)
        super(req, sess, cust, locale_override, business_data: error_data)
      end
    end

    # The robots.txt file
    class RobotsTxt < Manifold::Views::BaseView

    end

    class UnknownSecret < Manifold::Views::BaseView

    end
  end
end

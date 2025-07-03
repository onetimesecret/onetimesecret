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
    #   view = Manifold::Views::VuePoint.new
    #
    class VuePoint < Manifold::Views::BaseView


      def init *args; end
    end

    class ExportWindow < Manifold::Views::BaseView
      # require 'views/example.rue'

      def init *args; end
    end

    class Error < Manifold::Views::BaseView
      def init *_args
        self[:title] = "I'm afraid there's been an error"
      end
    end

    # The robots.txt file
    class RobotsTxt < Manifold::Views::BaseView

    end

    class UnknownSecret < Manifold::Views::BaseView

    end
  end
end

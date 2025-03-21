# apps/web/core/views.rb

require_relative 'views/base'

module Core

  module Views

    ##
    # The VuePoint class serves as a bridge between the Ruby Rack application
    # and the Vue.js frontend. It is responsible for initializing and passing
    # JavaScript variables from the backend to the frontend.
    #
    # Example usage:
    #   view = Onetime::App::Views::VuePoint.new
    #
    class VuePoint < Core::View
      self.template_name = 'index'
      def init *args
      end
    end

    class Error < Core::View
      def init *args
        self[:title] = "I'm afraid there's been an error"
      end
    end

    # The robots.txt file
    class RobotsTxt < Core::View
      self.template_name = 'robots'
      self.template_extension = 'txt'
    end

    class UnknownSecret < Core::View
      self.template_name = :index
    end

  end
end

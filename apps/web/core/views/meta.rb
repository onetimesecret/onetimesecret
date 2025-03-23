# apps/web/core/views/meta.rb

require_relative 'base'

module Core
  module Views

    ##
    # The VuePoint class serves as a bridge between the Ruby Rack application
    # and the Vue.js frontend. It is responsible for initializing and passing
    # JavaScript variables from the backend to the frontend.
    #
    # Example usage:
    #   view = Core::Views::VuePoint.new
    #
    class VuePoint < Core::Views::BaseView
      self.template_name = 'index'
      def init *args
      end
    end

    class Error < Core::Views::BaseView
      def init *args
        self[:title] = "I'm afraid there's been an error"
      end
    end

    # The robots.txt file
    class RobotsTxt < Core::Views::BaseView
      self.template_name = 'robots'
      self.template_extension = 'txt'
    end

    class UnknownSecret < Core::Views::BaseView
      self.template_name = :index
    end

  end
end

# apps/web/manifold/views.rb

require_relative 'views/base'

module Manifold
  module Views
    ##
    # The VuePoint class serves as a bridge between the Ruby Rack application
    # and the Vue.js frontend. It is responsible for initializing and passing
    # JavaScript variables from the backend to the frontend.
    #
    # Example usage:
    #   view = Manifold::Views::VuePoint.new
    #
    class VuePoint < Manifold::Views::BaseView
      self.template_name = 'index'

      use_serializers(
        # ConfigSerializer,
        # AuthenticationSerializer,
        # DomainSerializer,
        # I18nSerializer,
        # MessagesSerializer,
        # # PlanSerializer,
        # SystemSerializer,
      )

      def init *args; end
    end

    class ExportWindow < Manifold::Views::BaseView
      self.template_name = nil

      use_serializers(
        # ConfigSerializer,
        # AuthenticationSerializer,
        # DomainSerializer,
        # I18nSerializer,
        # MessagesSerializer,
        # PlanSerializer,
        # SystemSerializer,
      )

      def init *args; end
    end

    class Error < Manifold::Views::BaseView
      def init *_args
        self[:title] = "I'm afraid there's been an error"
      end
    end

    # The robots.txt file
    class RobotsTxt < Manifold::Views::BaseView
      self.template_name      = 'robots'
      self.template_extension = 'txt'
    end

    class UnknownSecret < Manifold::Views::BaseView
      self.template_name = :index
    end
  end
end

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
    #   view = Core::Views::VuePoint.new(req, sess, cust, locale)
    #   html = view.render('index')
    #
    class VuePoint < Core::Views::BaseView
      use_serializers(
        ConfigSerializer,
        AuthenticationSerializer,
        DomainSerializer,
        I18nSerializer,
        MessagesSerializer,
        SystemSerializer,
      )

      def init(*args); end
    end

    class ExportWindow < Core::Views::BaseView
      use_serializers(
        ConfigSerializer,
        AuthenticationSerializer,
        DomainSerializer,
        I18nSerializer,
        MessagesSerializer,
        SystemSerializer,
      )

      def init(*args); end
    end

    class Error < Core::Views::BaseView
      def init(*_args)
        # Note: Rhales doesn't use self[:key] assignment
        # Error handling will need to be refactored
      end
    end

    # The robots.txt file
    class RobotsTxt < Core::Views::BaseView
      def init(*_args); end

      def render(template_name = 'robots')
        super(template_name)
      end
    end

    class UnknownSecret < Core::Views::BaseView
      def init(*_args); end
    end
  end
end

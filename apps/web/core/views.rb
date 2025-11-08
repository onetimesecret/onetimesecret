# apps/web/core/views.rb
#
# frozen_string_literal: true

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
      attr_accessor :error_id, :timestamp, :environment, :error_message, :error_class

      def init(error_id: nil, error_message: nil, error_class: nil)
        @error_id      = error_id || SecureRandom.uuid
        @timestamp     = Time.now.utc.iso8601
        @environment   = ENV['RACK_ENV'] || 'production'
        @error_message = error_message
        @error_class   = error_class
      end

      def render(template_name = 'error')
        # Add error-specific data to serialized_data for window.__ERROR_STATE__
        @serialized_data.merge!(
          'error_id' => error_id,
          'timestamp' => timestamp,
          'environment' => environment,
          'error_message' => error_message,
          'error_class' => error_class,
        )

        super
      end
    end

    # The robots.txt file
    class RobotsTxt < Core::Views::BaseView
      def init(*_args); end

      def render(template_name = 'robots')
        # Override to return plain text without hydration
        # Template-only variables (NOT serialized to window state)
        template_vars = {
          'baseuri' => view_vars['baseuri'],
        }

        rhales_view = Rhales::View.new(
          req,
          client: {},                   # No client data for robots.txt
          server: template_vars,        # Only baseuri for template
          config: Rhales.configuration,
        )

        rhales_view.render(template_name)
      end
    end

    class UnknownSecret < Core::Views::BaseView
      def init(*_args); end
    end
  end
end

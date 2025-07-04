# apps/web/manifold/views.rb

require 'onetime/refinements/require_refinements'

require_relative 'views/base'

module Manifold
  module Views
    using Onetime::Ruequire

    ##
    # Standard view class for simple templates with automatic configuration
    # Automatically resolves templates and sets appropriate headers/status codes
    #
    class StandardView < Manifold::Views::BaseView
      class << self
        # Configure content type for this view class
        def content_type(type = nil)
          @content_type = type if type
          @content_type || 'text/html'
        end

        # Configure HTTP status code for this view class
        def status_code(code = nil)
          @status_code = code if code
          @status_code || 200
        end

        # Template name override (defaults to class name)
        def template_name(name = nil)
          @template_name = name if name
          @template_name || self.name.split('::').last.downcase
        end
      end

      def render(template_name = nil)
        # Use class-level template name if not specified
        template_name ||= self.class.template_name
        super
      end
    end

    ##
    # The VuePoint class serves as a bridge between the Ruby Rack application
    # and the Vue.js frontend. Uses the standard index.rue template.
    #
    class VuePoint < StandardView
      # Uses default: index.rue template, text/html content-type, 200 status
      template_name 'index'
    end

    ##
    # ExportWindow returns JSON data for the OnetimeWindow structure
    #
    class ExportWindow < StandardView
      content_type 'application/json'

      # Override to return SPA JSON data instead of template
      def render(_template_name = nil)
        self.class.render_spa(@req, @sess, @cust, @locale)
      end
    end

    ##
    # Error page with custom title
    #
    class Error < StandardView
      def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {})
        # Add default title to business data
        error_data = { title: "I'm afraid there's been an error" }.merge(business_data)
        super(req, sess, cust, locale_override, business_data: error_data)
      end
    end

    ##
    # The robots.txt file - returns plain text
    #
    class RobotsTxt < StandardView
      content_type 'text/plain'
      template_name 'robots'
    end

    ##
    # 404 page for unknown secrets
    #
    class UnknownSecret < StandardView
      status_code 404
      template_name 'unknown_secret'
    end
  end
end

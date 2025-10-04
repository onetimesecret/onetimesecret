# apps/web/core/views/base.rb

require 'chimera'

require 'onetime/middleware'

require 'v2/models/customer'

require_relative 'helpers'
require_relative 'serializers'

# Core view framework with helpers and serializers
#
# This file defines the BaseView class which serves as the foundation for all views in the application.
# It provides:
#
# - **Helpers**: Utility methods for view rendering and data manipulation
# - **Serializers**: Transform internal view state for frontend consumption
#
module Core
  module Views
    class BaseView < Chimera
      extend Core::Views::InitializeViewVars
      include Core::Views::SanitizerHelpers
      include Core::Views::I18nHelpers
      include Core::Views::ViteManifest
      include Onetime::Utils::TimeUtils

      self.template_path      = './templates/web'
      self.template_extension = 'html'
      self.view_namespace     = Core::Views
      self.view_path          = './app/web/views'

      attr_accessor :req, :sess, :cust, :locale, :form_fields, :pagename
      attr_reader :i18n_instance, :view_vars, :serialized_data, :messages

      def initialize(req, sess = nil, cust = nil, locale_override = nil, *)
        @req  = req
        @sess = sess
        @cust = cust || V2::Customer.anonymous

        # We determine locale here because it's used for i18n. Otherwise we couldn't
        # determine the i18n messages until inside or after initialize_view_vars.
        #
        # Determine locale with this priority:
        # 1. Explicitly provided locale
        # 2. Locale from request environment (if available)
        # 3. Application default locale as set in yaml configuration
        @locale = if locale_override
                    locale_override
                  elsif !req.nil? && req.env['ots.locale']
                    req.env['ots.locale']
                  else
                    OT.default_locale
                  end

        @i18n_instance = i18n
        @messages      = []

        update_view_vars

        init(*) if respond_to?(:init)

        update_serialized_data
      end

      def update_serialized_data
        @serialized_data = run_serializers
      end

      def update_view_vars
        @view_vars = self.class.initialize_view_vars(req, sess, cust, locale, i18n_instance)

        # Make the view-relevant variables available to the view and HTML
        # template. We're intentionally not calling self[key.to_s] here as
        # a defensive measure b/c it can obscure situations where the key
        # is not a string, it's "corrected" here, but may not be in another
        # part of the code.
        @view_vars.each do |key, value|
          self[key] = value
        end
      end

      # Add notification message to be displayed in StatusBar component
      #
      # @param msg [String] Message content to be displayed
      # @param type [String] Type of message, one of: info, error, success, warning
      # @return [Array<Hash>] Array containing all message objects
      def add_message(msg, type = 'info')
        messages << { 'type' => type, 'content' => msg }
      end

      # Add error message to be displayed in StatusBar component
      #
      # @param msg [String] error message content to be displayed
      # @return [Array<Hash>] array containing all message objects
      def add_error(msg)
        add_message(msg, 'error')
      end

      # Run all registered serializers to transform view data for frontend consumption
      #
      # Executes each serializer registered for this view in dependency order,
      # merging their results into a single data structure that can be safely
      # passed to the frontend.
      #
      # @return [Hash] The serialized data
      def run_serializers
        SerializerRegistry.run(self.class.serializers, view_vars, i18n_instance)
      end

      class << self
        # pagename is used in the i18n[:web][:pagename] hash which (if present)
        # provides the locale strings specifically for this view. For that to
        # work, the view being used has a matching name in the locales file.
        def pagename
          # NOTE: There's some speculation that setting a class instance variable
          # inside the class method could present a race condition in between the
          # check for nil and running the expression to set it. It's possible but
          # every thread will produce the same result. Winning by technicality is
          # one thing but the reality of software development is another. Process
          # is more important than clever design. Instead, a safer practice is to
          # set the class instance variable here in the class definition.
          @pagename ||= name.split('::').last.downcase.to_sym
        end

        # Class-level serializers list
        #
        # @return [Array<Module>] List of serializers to use with this view
        def serializers
          @serializers ||= []
        end

        # Add serializers to this view
        #
        # @param serializer_list [Array<Module>] List of serializers to add to this view
        # @return [Array<Module>] Updated list of serializers
        def use_serializers(*serializer_list)
          serializer_list.each do |serializer|
            serializers << serializer unless serializers.include?(serializer)
          end
        end
      end
    end
  end
end

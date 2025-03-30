# apps/web/core/views/base.rb

require 'chimera'

require 'onetime/middleware'

require 'v2/models/customer'

require_relative 'helpers'
require_relative 'serializers'
#
# - **Helpers**: Provide utility methods for internal use
# - **Serializers**: Transform internal state for frontend consumption
#
module Core
  module Views
    class BaseView < Chimera
      extend Core::Views::InitializeViewVars
      include Core::Views::SanitizerHelpers
      include Core::Views::I18nHelpers
      include Core::Views::ViteManifest
      include Onetime::TimeUtils

      self.template_path = './templates/web'
      self.template_extension = 'html'
      self.view_namespace = Core::Views
      self.view_path = './app/web/views'

      attr_accessor :req, :sess, :cust, :locale, :messages, :form_fields, :pagename
      attr_reader :view_vars, :i18n_instance, :serialized_data

      def initialize req, sess=nil, cust=nil, locale=nil, *args
        @req = req
        @sess = sess
        @cust = cust || V2::Customer.anonymous
        @locale = locale || (req.nil? ? OT.default_locale : req.env['ots.locale'])
        @messages = []

        @i18n_instance = self.i18n
        @view_vars = self.class.initialize_vars(req, sess, cust, locale, i18n_instance)

        # Make the view-relevant variables available to the view and HTML template
        @view_vars.each do |key, value|
          self[key] = value
        end

        init(*args) if respond_to?(:init)

        # Run serializers and apply to view
        @serialized_data = self.run_serializers
      end

      # Add notification message to be displayed in StatusBar component
      # @param msg [String] message content to be displayed
      # @param type [String] type of message, one of: info, error, success (default: 'info')
      # @return [Array<Hash>] array containing message objects {type: String, content: String}
      def add_message msg, type='info'
        messages << {type: type, content: msg}
      end

      # Add error message to be displayed in StatusBar component
      # @param msg [String] error message content to be displayed
      # @return [Array<Hash>] array containing message objects {type: String, content: String}
      def add_error msg
        add_message(msg, 'error')
      end

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
          @pagename ||= self.name.split('::').last.downcase.to_sym
        end

        # Class-level serializers list
        def serializers
          @serializers ||= []
        end

        # Add serializers to this view
        def use_serializers(*serializer_list)
          serializer_list.each do |serializer|
            serializers << serializer unless serializers.include?(serializer)
          end
        end
      end

    end
  end
end

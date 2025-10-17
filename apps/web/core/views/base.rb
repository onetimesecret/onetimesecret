# apps/web/core/views/base.rb

require 'rhales'

require 'onetime/middleware'

require 'onetime/models'

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
    class BaseView
      extend Core::Views::InitializeViewVars
      include Core::Views::SanitizerHelpers
      include Core::Views::I18nHelpers
      include Core::Views::ViteManifest
      include Onetime::Utils::TimeUtils

      # include Onetime::Helpers::ShrimpHelpers

      TEMPLATE_PATH = File.join(__dir__, '..', 'templates')

      attr_accessor :req, :sess, :cust, :locale, :form_fields, :pagename
      attr_reader :i18n_instance, :view_vars, :serialized_data, :messages

      def initialize(req, sess = nil, cust = nil, locale_override = nil, *)
        @req  = req
        @sess = sess
        @cust = cust || Onetime::Customer.anonymous

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

        # Initialize view variables for use in rendering
        @view_vars = self.class.initialize_view_vars(req, sess, cust, locale, i18n_instance)

        # Call subclass init hook if defined
        init(*) if respond_to?(:init)

        # Run serializers to prepare data for frontend
        @serialized_data = run_serializers
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

      # Render the view using Rhales
      #
      # Separates data into two categories:
      # 1. Window state (serialized_data) - goes into window.__ONETIME_STATE__
      # 2. Template vars - used for HTML rendering only
      #
      # @param template_name [String] Optional template name (defaults to 'index')
      # @return [String] Rendered HTML
      def render(template_name = 'index')
        # Template-only variables (NOT serialized to window.__ONETIME_STATE__)
        # These are available in templates via {{variable}} but won't reach the client
        template_vars = {
          'page_title' => view_vars['page_title'],
          'description' => view_vars['description'],
          'keywords' => view_vars['keywords'],
          'baseuri' => view_vars['baseuri'],
          'site_host' => view_vars['site_host'],
          'no_cache' => view_vars['no_cache'],
          'vite_assets_html' => vite_assets(
            nonce: view_vars['nonce'],
            development: view_vars['frontend_development']
          )
        }

        # Wrap session to provide authenticated? method
        adapted_session = OnetimeSessionAdapter.new(sess)

        # Create Rhales view with separated data
        # - client: Data from serializers that goes to window.__ONETIME_STATE__
        # - server: Template-only variables that don't get serialized to client
        rhales_view = Rhales::View.new(
          req,
          adapted_session,
          cust,
          locale,
          client: serialized_data,      # Only this goes to window state
          server: template_vars,        # Available in templates, NOT serialized
          config: Rhales.configuration
        )

        rhales_view.render(template_name)
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

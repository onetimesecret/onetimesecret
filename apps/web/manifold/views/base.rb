# apps/web/ui/views/base.rb

require 'chimera'

require 'onetime/middleware'
require 'onetime/services/ui/ui_context'

require_relative 'helpers'

# Core view framework with helpers and serializers
#
# This file defines the BaseView class which serves as the foundation for all views in the application.
# It provides:
#
# - **Helpers**: Utility methods for view rendering and data manipulation
#
module Manifold
  module Views
    class BaseView < Chimera
      # extend OT::Services::UI::UIContext
      include Manifold::Views::SanitizerHelpers
      include Manifold::Views::I18nHelpers
      include Manifold::Views::ViteManifest
      include Onetime::TimeUtils

      self.template_path      = './templates/web'
      self.template_extension = 'html'
      self.view_namespace     = Manifold::Views
      self.view_path          = './app/web/manifold/views'

      attr_accessor :req, :sess, :cust, :locale, :form_fields, :pagename
      attr_reader :i18n_instance, :view_vars, :serialized_data, :messages

      def initialize(req, sess = nil, cust = nil, locale_override = nil, *)
        @req  = req
        @sess = sess

        @cust = cust || anonymous_customer

        # We determine locale here because it's used for i18n. Otherwise we couldn't
        # determine the i18n messages until inside or after template_vars.
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
                    OT.conf[:default_locale]
                  end

        @i18n_instance = i18n
        @messages      = []

        # @view_vars = self.class.template_vars(req, sess, cust, locale, i18n_instance)

        # Make the view-relevant variables available to the view and HTML template
        # @view_vars.each do |key, value|
        #   self[key] = value
        # end

        init(*) if respond_to?(:init)

        # @serialized_data = run_serializers
      end

      def anonymous_customer
        # Lazy-load the model here if we need to. Running tests for example,
        # in some cases won't have a database connection.
        require 'v2/models/customer' unless defined?(V2::Customer)
        @cust = V2::Customer.anonymous
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
      end
    end
  end
end

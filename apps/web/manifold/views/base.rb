# apps/web/manifold/views/base.rb

require 'onetime/middleware'
require 'onetime/rsfc/view'
require 'onetime/rsfc/onetime_window_bridge'

require_relative 'helpers'

# Core view framework with RSFC template support
#
# This file defines the BaseView class which serves as the foundation for all views in the application.
# Migrated from Mustache to RSFC (Ruby Single File Components) for better server-to-client data flow.
#
# Key changes from Mustache version:
# - Extends RSFC::View instead of Mustache
# - Removed Mustache-specific configurations (template_path, template_extension, etc.)
# - Maintains compatibility with existing helpers and patterns
# - Supports .rue template files with automatic data hydration
#
module Manifold
  module Views
    class BaseView < Onetime::RSFC::View
      include Manifold::Views::SanitizerHelpers
      include Manifold::Views::I18nHelpers
      include Manifold::Views::ViteManifest
      include Onetime::TimeUtils

      attr_accessor :form_fields, :pagename
      attr_reader :i18n_instance, :messages

      def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {})
        # Determine locale with same priority as before
        resolved_locale = if locale_override
                            locale_override
                          elsif !req.nil? && req.env['ots.locale']
                            req.env['ots.locale']
                          else
                            OT.conf[:default_locale]
                          end

        # Call parent RSFC::View constructor
        super(req, sess, cust, resolved_locale, business_data: business_data)

        # Initialize i18n and messages
        @i18n_instance = i18n
        @messages      = sess&.get_messages || []

        # Call init hook if present (maintains compatibility)
        init if respond_to?(:init)
      end

      # Override RSFC::View render to include i18n, messages, and OnetimeWindow context
      def render(template_name = nil)
        # Add i18n, messages, and OnetimeWindow data to business data
        enhanced_business_data = @business_data.merge(
          i18n: @i18n_instance,
          messages: @messages,
          pagename: self.class.pagename,
          onetime_window: onetime_window_data,
        )

        # Create new context with enhanced data
        @rsfc_context = Onetime::RSFC::Context.for_view(@req, @sess, @cust, @locale, **enhanced_business_data)

        # Render with enhanced context
        super
      end

      # Access to i18n data for templates
      def i18n
        @i18n_instance ||= begin
          # require 'onetime/utils/i18n' # TODO: Where did this file go?

          i18n_data = if OT.conf && OT.conf['i18n']
            OT.conf['i18n']
          else
            {}
          end

          # Add locale-specific data
          locale_data = i18n_data[@locale] || i18n_data[@locale.to_s] || {}

          # Merge common and locale-specific data
          common_data = i18n_data['COMMON'] || {}
          common_data.merge(locale_data)
        end
      end

      # Access to OnetimeWindow data from templates
      def onetime_window_data
        @onetime_window_data ||= Onetime::RSFC::OnetimeWindowBridge.build_onetime_window_data(@req, @sess, @cust, @locale)
      end

      # Provide direct access to specific OnetimeWindow fields commonly used in templates
      def authenticated?
        onetime_window_data[:authenticated]
      end

      def site_host
        onetime_window_data[:site_host]
      end

      def baseuri
        onetime_window_data[:baseuri]
      end

      def shrimp
        onetime_window_data[:shrimp]
      end

      class << self
        # pagename is used in the i18n[:web][:pagename] hash which (if present)
        # provides the locale strings specifically for this view. For that to
        # work, the view being used has a matching name in the locales file.
        def pagename
          @pagename ||= name.split('::').last.downcase.to_sym
        end

        # Convenience method to render with business data (maintains API compatibility)
        def render_with_context(req, sess, cust, locale, **business_data)
          view = new(req, sess, cust, locale, business_data: business_data)
          view.render
        end

        # Render for SPA mode (Vue frontend) - returns JSON data only
        def render_spa(req, sess, cust, locale)
          onetime_data = Onetime::RSFC::OnetimeWindowBridge.build_onetime_window_data(req, sess, cust, locale)
          JSON.pretty_generate(onetime_data)
        end

        # Render full page with RSFC template and OnetimeWindow compatibility
        def render_page(req, sess, cust, locale, **business_data)
          view = new(req, sess, cust, locale, business_data: business_data)

          # Get OnetimeWindow data for hydration
          onetime_data = Onetime::RSFC::OnetimeWindowBridge.build_onetime_window_data(req, sess, cust, locale)

          # Add to business data for template access
          view.instance_variable_set(:@onetime_window_data, onetime_data)

          view.render
        end

        # Enhanced render method that includes OnetimeWindow data
        def render_with_data(req, sess, cust, locale, **business_data)
          # Combine RSFC data with OnetimeWindow data
          rsfc_data = Onetime::RSFC::OnetimeWindowBridge.build_rsfc_data(req, sess, cust, locale)
          combined_data = business_data.merge(rsfc_data)

          view = new(req, sess, cust, locale, business_data: combined_data)
          view.render
        end
      end
    end
  end
end

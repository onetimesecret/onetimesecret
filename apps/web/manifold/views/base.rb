# apps/web/manifold/views/base.rb

require 'onetime/middleware'
require 'rhales'
require 'onetime/services/ui/ui_context'

require_relative 'helpers'

# Core view framework with Rhales template support
#
# This file defines the BaseView class which serves as the foundation for all views in the application.
# Migrated from Mustache to Rhales (Ruby Single File Components) for better server-to-client data flow.
#
# Key changes from Mustache version:
# - Extends Rhales::View instead of Mustache
# - Removed Mustache-specific configurations (template_path, template_extension, etc.)
# - Maintains compatibility with existing helpers and patterns
# - Supports .rue template files with automatic data hydration and CSP support
#
module Manifold
  module Views
    class BaseView < Rhales::View
      include Manifold::Views::SanitizerHelpers
      include Manifold::Views::I18nHelpers
      include Manifold::Views::ViteManifest
      include Onetime::TimeUtils

      attr_accessor :form_fields, :pagename
      attr_reader :i18n_instance, :messages

      def initialize(req, sess = nil, cust = nil, locale_override = nil, props: {})
        # Call parent constructor which will create the appropriate context
        super

        # Update instance variables from context
        @cust   = @rsfc_context.cust
        @locale = @rsfc_context.locale

        # Initialize i18n and messages
        @i18n_instance = i18n
        @messages      = @rsfc_context.get('onetime_window.messages') || []

        # Call init hook if present (maintains compatibility)
        init if respond_to?(:init)
      end

      # Use Onetime::Services::UIContext instead of RSFC::Context
      def context_class
        OT.ld "[BaseView] context_class from #{caller[1..1]}" if OT.debug?

        Onetime::Services::UIContext
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

      # Access to OnetimeWindow data from UIContext
      def onetime_window_data
        @rsfc_context.get('onetime_window')
      end

      # Provide direct access to specific OnetimeWindow fields commonly used in templates
      def authenticated?
        @rsfc_context.get('onetime_window.authenticated')
      end

      def site_host
        @rsfc_context.get('onetime_window.site_host')
      end

      def baseuri
        @rsfc_context.get('onetime_window.baseuri')
      end

      def shrimp
        @rsfc_context.get('onetime_window.shrimp')
      end

      class << self
        # pagename is used in the i18n[:web][:pagename] hash which (if present)
        # provides the locale strings specifically for this view. For that to
        # work, the view being used has a matching name in the locales file.
        def pagename
          @pagename ||= name.split('::').last.downcase.to_sym
        end

        # Convenience method to render with business data (maintains API compatibility)
        def render_with_context(req, sess, cust, locale, **props)
          view = new(req, sess, cust, locale, props: props)
          view.render
        end

        # Render for SPA mode (Vue frontend) - returns JSON data only
        def render_spa(req, sess, cust, locale)
          ui_context   = Onetime::Services::UIContext.new(req, sess, cust, locale)
          onetime_data = ui_context.get('onetime_window')
          JSON.pretty_generate(onetime_data)
        end

        # Render full page with Rhales template and OnetimeWindow compatibility
        def render_page(req, sess, cust, locale, **props)
          view = new(req, sess, cust, locale, props: props)
          view.render
        end

        # Enhanced render method that includes OnetimeWindow data
        def render_with_data(req, sess, cust, locale, **props)
          view = new(req, sess, cust, locale, props: props)
          view.render
        end
      end
    end
  end
end

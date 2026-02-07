# lib/onetime/mail/views/base.rb
#
# frozen_string_literal: true

require 'erb'
require 'yaml'

module Onetime
  module Mail
    module Templates
      # DEPRECATED: EmailTranslations class
      #
      # This class has been replaced by the ruby-i18n gem. It's kept for
      # backward compatibility during the migration but will be removed.
      #
      # Use I18n.t() directly instead:
      #   I18n.t('email.organization_invitation.subject', locale: 'en')
      #
      class EmailTranslations
        class << self
          # Delegate to I18n.t() for translation lookups
          #
          # @param key [String] Translation key
          # @param locale [String] Locale code
          # @param options [Hash] Interpolation options
          # @return [String] Translated string
          #
          def translate(key, locale: 'en', **)
            I18n.t(key, locale: locale.to_sym, **)
          end

          # No-op for backward compatibility
          def reset!
            # I18n doesn't need manual cache clearing
          end
        end
      end

      # Base class for email templates using ERB.
      #
      # Subclasses define template-specific data and subject lines.
      # Templates are loaded from lib/onetime/mail/templates/ directory.
      #
      # Design notes for future ruby-i18n integration:
      # - Template data is passed as a hash, not instance variables
      # - Subject lines are defined as methods that can call I18n.t()
      # - Template files can use <%= t('key') %> when i18n is added
      # - The `t` helper method is already stubbed for future use
      #
      # Example usage:
      #   template = SecretLink.new(
      #     secret: secret,
      #     recipient: "user@example.com",
      #     sender_email: "sender@example.com",
      #     locale: 'en'
      #   )
      #   template.render_text  # => rendered text content
      #   template.render_html  # => rendered HTML content
      #   template.subject      # => email subject line
      #
      class Base
        TEMPLATE_PATH = File.expand_path('../templates', __dir__)

        attr_reader :data, :locale

        # @param data [Hash] Template variables
        # @param locale [String] Locale code (default: 'en')
        def initialize(data = {}, locale: 'en')
          @data   = data
          @locale = locale
          validate_data!
        end

        # Email subject line - override in subclasses
        # @return [String]
        def subject
          raise NotImplementedError, "#{self.class} must implement #subject"
        end

        # Render the text template
        # @return [String]
        def render_text
          render_template('txt')
        end

        # Render the HTML template
        # @return [String, nil] nil if no HTML template exists
        def render_html
          render_template('html')
        rescue Errno::ENOENT
          # HTML template is optional
          nil
        end

        # Build complete email hash ready for delivery
        # @param from [String] Sender email address
        # @param reply_to [String, nil] Reply-to address
        # @return [Hash]
        def to_email(from:, reply_to: nil)
          {
            to: recipient_email,
            from: from,
            reply_to: reply_to,
            subject: subject,
            text_body: render_text,
            html_body: render_html,
          }
        end

        protected

        # Override in subclasses to validate required data
        def validate_data!
          # Base implementation does nothing
        end

        # Template name derived from class name
        # SecretLink -> secret_link
        # @return [String]
        def template_name
          self.class.name
            .split('::').last
            .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
            .gsub(/([a-z\d])([A-Z])/, '\1_\2')
            .downcase
        end

        # Get the recipient email from data
        # Override in subclasses if recipient is stored differently
        # @return [String]
        def recipient_email
          data[:recipient] || data[:email_address] || data[:to]
        end

        # Site SSL configuration helper
        # @return [Boolean]
        def site_ssl?
          return true unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'ssl') != false
        end

        # Site host configuration helper
        # @return [String]
        def site_host
          return 'onetimesecret.com' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'host') || 'onetimesecret.com'
        end

        # Site base URI configuration helper
        # @return [String]
        def site_baseuri
          scheme = site_ssl? ? 'https://' : 'http://'
          "#{scheme}#{site_host}"
        end

        # Site product name configuration helper
        # @return [String]
        def site_product_name
          return 'Onetime Secret' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'product_name') || 'Onetime Secret'
        end

        # Product name with fallback to site config
        # @return [String]
        def product_name
          data[:product_name] || site_product_name
        end

        # Display domain with fallback to site host
        # @return [String]
        def display_domain
          data[:display_domain] || site_host
        end

        private

        def render_template(extension)
          template_file    = File.join(TEMPLATE_PATH, "#{template_name}.#{extension}.erb")
          template_content = File.read(template_file)

          # Create a binding with access to data and helpers
          erb = ERB.new(template_content, trim_mode: '-')
          erb.result(template_binding)
        end

        # Create a binding for ERB template rendering
        # This provides access to data hash and helper methods
        def template_binding
          # Make data keys available as local-ish methods via method_missing
          TemplateContext.new(data, locale).get_binding
        end

        # Helper class to provide clean binding for ERB templates
        class TemplateContext
          def initialize(data, locale)
            @data   = data
            @locale = locale
          end

          def get_binding
            binding
          end

          # Access data values like methods: <%= secret_uri %>
          def method_missing(name, *args)
            if @data.key?(name)
              @data[name]
            elsif @data.key?(name.to_s)
              @data[name.to_s]
            else
              super
            end
          end

          def respond_to_missing?(name, include_private = false)
            @data.key?(name) || @data.key?(name.to_s) || super
          end

          # Translation helper for email templates
          # Loads translations from config/locales/email/*.yml
          # @param key [String] Translation key (e.g., 'email.organization_invitation.subject')
          # @param options [Hash] Interpolation options
          # @return [String] Translated string
          def t(key, **)
            EmailTranslations.translate(key, locale: @locale, **)
          end

          # HTML escape helper
          # @param text [String]
          # @return [String]
          def h(text)
            ERB::Util.html_escape(text)
          end

          # URL encode helper
          # @param text [String]
          # @return [String]
          def u(text)
            ERB::Util.url_encode(text)
          end

          # Site base URI helper
          # @return [String]
          def baseuri
            @data[:baseuri] || site_baseuri
          end

          # Product name helper (organization name or default)
          # @return [String]
          def product_name
            @data[:product_name] || site_product_name
          end

          # Display domain helper (custom domain or canonical)
          # @return [String]
          def display_domain
            @data[:display_domain] || @data[:share_domain] || site_host
          end

          # Brand color helper - resolves from data, config, or default
          # @return [String] Hex color string
          def brand_color
            @data[:brand_color] || conf_dig('branding', 'primary_color') || '#dc4a22'
          end

          # Logo alt text helper - delegates to product_name
          # @return [String]
          def logo_alt
            product_name
          end

          # Get product name from site config
          def site_product_name
            @site_product_name ||= conf_dig('branding', 'product_name') || conf_dig('site', 'interface', 'ui', 'header', 'site_name') || t('email.common.onetime_secret')
          end

          # Get host from site config
          def site_host
            @site_host ||= conf_dig('site', 'host') || 'onetimesecret.com'
          end

          # Get base URI from site config
          def site_baseuri
            @site_baseuri ||= begin
              scheme = conf_dig('site', 'ssl') == false ? 'http://' : 'https://'
              host   = conf_dig('site', 'host') || 'localhost'
              "#{scheme}#{host}"
            end
          end

          private

          def conf_dig(*keys)
            return nil unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

            OT.conf.dig(*keys)
          end
        end
      end
    end
  end
end

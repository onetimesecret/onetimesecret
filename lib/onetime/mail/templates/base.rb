# lib/onetime/mail/templates/base.rb
#
# frozen_string_literal: true

require 'erb'

module Onetime
  module Mail
    module Templates
      # Base class for email templates using ERB.
      #
      # Subclasses define template-specific data and subject lines.
      # Templates are loaded from templates/mail/ directory.
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
        TEMPLATE_PATH = File.expand_path('../../../../templates/mail', __dir__)

        attr_reader :data, :locale

        # @param data [Hash] Template variables
        # @param locale [String] Locale code (default: 'en')
        def initialize(data = {}, locale: 'en')
          @data = data
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
            html_body: render_html
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

        private

        def render_template(extension)
          template_file = File.join(TEMPLATE_PATH, "#{template_name}.#{extension}.erb")
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
            @data = data
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

          # Future i18n helper - stub for now
          # When ruby-i18n is integrated, this will call I18n.t()
          # @param key [String] Translation key
          # @param options [Hash] Interpolation options
          # @return [String]
          def t(key, **options)
            # TODO: Replace with I18n.t(key, locale: @locale, **options)
            # For now, return the key as a placeholder
            key.to_s
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

          # Get base URI from site config
          def site_baseuri
            return @site_baseuri if defined?(@site_baseuri)

            if defined?(OT) && OT.respond_to?(:conf)
              site = OT.conf.dig('site') || {}
              scheme = site['ssl'] ? 'https://' : 'http://'
              host = site['host'] || 'localhost'
              @site_baseuri = "#{scheme}#{host}"
            else
              @site_baseuri = 'https://onetimesecret.com'
            end
          end
        end
      end
    end
  end
end

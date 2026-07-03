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

        # Whether render_text wraps the body in the shared text layout
        # (layout.txt.erb, which appends the product footer plus the
        # conditional support line). Defaults to true. A subclass opts out at
        # its own definition site with `text_layout false`, so the rationale
        # for opting out travels with the declaration. See #3362.
        @text_layout = true

        class << self
          # Declarative per-template switch for the shared text layout. Call in
          # a subclass body: `text_layout false`.
          def text_layout(enabled)
            @text_layout = enabled
          end

          # Whether this template wraps its text body in the shared layout.
          # `!= false` so subclasses that never declare (nil) default to on.
          def text_layout?
            @text_layout != false
          end
        end

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

        # Render the text template, wrapped in the shared text layout.
        #
        # Mirrors render_html: the per-template file provides only the body
        # content; layout.txt.erb supplies the consolidated footer (product
        # name, base URI) plus the conditional BRAND_SUPPORT_EMAIL line so the
        # plaintext/multipart-fallback path carries the support contact too.
        # Before #3362 render_text used no layout, so the support contact was
        # wired into the HTML footer only and omitted from plaintext.
        #
        # Templates that opt out (`text_layout false`) keep their own footer
        # and are returned unwrapped. wrap_in_layout guards on File.exist?, so a
        # missing layout.txt.erb yields unwrapped content rather than raising;
        # the rescue below only covers subclasses with no .txt.erb at all.
        #
        # @return [String, nil] nil if the subclass has no .txt.erb template
        def render_text
          content = render_template('txt')
          return content unless self.class.text_layout?

          wrap_in_layout(content, 'txt')
        rescue Errno::ENOENT
          # No .txt.erb for this subclass (html-only mailer); mirrors render_html.
          nil
        end

        # Render the HTML template, wrapped in the shared layout.
        #
        # The per-template file (e.g. secret_link.html.erb) provides only the
        # body content; layout.html.erb supplies the shared shell, branded
        # header, and footer so every email shares one design system.
        #
        # @return [String, nil] nil if no HTML template exists
        def render_html
          content = render_template('html')
          wrap_in_layout(content, 'html')
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
          return 'localhost' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'host') || 'localhost'
        end

        # Site base URI configuration helper
        # @return [String]
        def site_baseuri
          scheme = site_ssl? ? 'https://' : 'http://'
          "#{scheme}#{site_host}"
        end

        # Install-wide product name for mail copy. brand.product_name is the
        # single authority (#3612); unconfigured installs fall through to the
        # neutral NEUTRAL_PRODUCT_NAME — never nil, since templates interpolate
        # the name into subjects and headers, and never an OTS-branded literal.
        def site_product_name
          OT.conf.dig('brand', 'product_name') ||
            Onetime::CustomDomain::BrandSettingsConstants::NEUTRAL_PRODUCT_NAME
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

        # Wrap rendered body content in the shared layout template.
        #
        # The layout only needs the generic helpers (product_name, baseuri,
        # show_logo?, t), so it renders against the raw data hash plus the
        # injected +content+ string. If no layout exists for the extension,
        # the content is returned unwrapped.
        #
        # @param content [String] Rendered body content
        # @param extension [String] Template extension (e.g. 'html')
        # @return [String]
        def wrap_in_layout(content, extension)
          layout_file = File.join(TEMPLATE_PATH, "layout.#{extension}.erb")
          return content unless File.exist?(layout_file)

          layout_content = File.read(layout_file)
          erb            = ERB.new(layout_content, trim_mode: '-')
          erb.result(layout_binding(content))
        end

        # Binding for the layout: raw data plus the injected body content.
        def layout_binding(content)
          TemplateContext.new(data.merge(content: content), locale).get_binding
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

          # Brand color helper - resolves from per-message data, brand config, or
          # the neutral default (#3B82F6) defined in BrandSettingsConstants.
          # @return [String] Hex color string
          def brand_color
            @brand_color ||= @data[:brand_color] ||
                             conf_dig('brand', 'primary_color') ||
                             Onetime::CustomDomain::BrandSettingsConstants::DEFAULTS[:primary_color]
          end

          # Support email helper - resolves from brand config or GLOBAL_DEFAULTS.
          # GLOBAL_DEFAULTS[:support_email] is nil per #3049 — operators must
          # set BRAND_SUPPORT_EMAIL to populate.
          # @return [String, nil]
          def support_email
            @support_email ||= conf_dig('brand', 'support_email') ||
                               Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:support_email]
          end

          # Email sign-off name. Resolves the configurable signature
          # independently of product_name so operators can sign mail with a
          # person or team without renaming the product everywhere else.
          #
          # Resolution order (highest priority first):
          #   1. @data[:signature_name] — optional per-message override.
          #   2. brand.signature_name (BRAND_SIGNATURE_NAME) — install-wide.
          #
          # Returns nil when unconfigured so templates fall back to the neutral
          # i18n default (email.*.signature, "Support Team") rather than a
          # hardcoded person's name. See docs/architecture/branding.md.
          # @return [String, nil]
          def signature_name
            return @signature_name if defined?(@signature_name)

            @signature_name = @data[:signature_name] ||
                              conf_dig('brand', 'signature_name')
          end

          # Logo alt text helper - operator-supplied brand.logo_alt
          # (BRAND_LOGO_ALT) when set, otherwise product_name so the logo's
          # accessible name matches the surrounding brand identity.
          # @return [String]
          def logo_alt
            conf_dig('brand', 'logo_alt') || product_name
          end

          # Logo URL helper - resolves from brand config; nil when no brand
          # logo is configured. Per #3049 the develop default of
          # "#{baseuri}/img/onetime-logo-v3-xl.svg" has been neutralized so
          # shipped/private-label instances don't leak OTS branding. Templates
          # check truthiness and render a text-only header when nil.
          #
          # Only absolute http(s) URLs are emitted: mail clients cannot
          # resolve relative paths or component references, and with the
          # legacy LOGO_URL now feeding brand.logo_url as a fallback (#3612),
          # a masthead-oriented relative path (e.g. /img/logo.png) must not
          # break email rendering — such values degrade to the text-only
          # header instead.
          # @return [String, nil]
          def logo_url
            return @logo_url if defined?(@logo_url)

            candidate = conf_dig('brand', 'logo_url') ||
                        Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:logo_url]
            @logo_url = candidate.to_s.match?(%r{\Ahttps?://}i) ? candidate : nil
          end

          # Mirrors Templates::Base#site_product_name: brand.product_name is
          # the single authority (#3612), with the neutral NEUTRAL_PRODUCT_NAME
          # terminal so layout copy never interpolates nil.
          def site_product_name
            @site_product_name ||=
              conf_dig('brand', 'product_name') ||
              Onetime::CustomDomain::BrandSettingsConstants::NEUTRAL_PRODUCT_NAME
          end

          # Get host from site config
          def site_host
            @site_host ||= conf_dig('site', 'host') || 'localhost'
          end

          # Get base URI from site config
          def site_baseuri
            @site_baseuri ||= begin
              scheme = conf_dig('site', 'ssl') == false ? 'http://' : 'https://'
              host   = conf_dig('site', 'host') || 'localhost'
              "#{scheme}#{host}"
            end
          end

          def show_logo?
            conf_dig('emailer', 'show_logo') == true
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

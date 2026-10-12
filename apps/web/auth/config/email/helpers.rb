# apps/web/auth/config/email/helpers.rb
#
# frozen_string_literal: true

require 'i18n'

module Auth::Config::Email
  module Helpers
    # The first candidate that names an available locale, as a String, or
    # I18n.default_locale.
    #
    # Every candidate is checked with I18n.locale_available?, the predicate
    # I18n.t's enforce_available_locales! raises on, so the result can never
    # make a template's I18n.t raise I18n::InvalidLocale. That raise mattered
    # beyond a broken email (SEC-B01): only an existing, eligible account
    # builds an email, so an unsupported `locale` request param answered 500
    # for an account and 200 for a missing login on the enumeration-safe
    # login-request routes (config/overrides/login_request_enumeration.rb).
    #
    # Matching is exact, against the locales the app loaded (strings and
    # symbols both match, e.g. 'fr_FR' and :fr_FR); a form the app does not
    # ship, such as 'fr-FR' or 'zz', is skipped rather than guessed at.
    # Surrounding whitespace is ignored; a non-String candidate (a nested
    # request param) never matches, and neither does a String with invalid
    # encoding, which `strip` would raise on (SEC-B01). Auth::ParamEncoding
    # refuses such a request before it gets here; this keeps the helper safe
    # for any other caller.
    #
    # @param candidates [Array<Object>] in priority order
    # @return [String]
    def self.available_locale(*candidates)
      candidates.each do |candidate|
        next unless candidate.is_a?(String) || candidate.is_a?(Symbol)
        next unless candidate.to_s.valid_encoding?

        name = candidate.to_s.strip
        return name if !name.empty? && I18n.locale_available?(name)
      end
      I18n.default_locale.to_s
    end

    def self.configure(auth)
      # Determine locale for current account/session
      # Priority: account preference > session > request param > default,
      # skipping any candidate the app has no locale for.
      # rubocop:disable-next Lint/NestedMethodDefinition -- Rodauth's auth_class_eval pattern
      auth.auth_class_eval do
        def determine_account_locale
          Auth::Config::Email::Helpers.available_locale(
            account[:locale],
            session[:locale],
            request.params['locale'],
          )
        end

        # Build multipart email (text + HTML) from template
        # @param template [Onetime::Mail::Templates::Base] Template instance
        # @return [Mail::Message] Multipart email message
        def build_multipart_email(template)
          html_body = template.render_html

          # If no HTML version, use simple text email
          return create_email(template.subject, template.render_text) unless html_body

          # Create multipart email with text and HTML versions
          # Rodauth's create_email signature: create_email(subject, body)
          mail = create_email(template.subject, '')

          # Add text part
          mail.text_part = Mail::Part.new do
            body template.render_text
          end

          # Add HTML part
          mail.html_part = Mail::Part.new do
            content_type 'text/html; charset=UTF-8'
            body html_body
          end

          mail
        end
      end
    end
  end
end

# apps/web/auth/config/email/helpers.rb
#
# frozen_string_literal: true

module Auth::Config::Email
  module Helpers
    def self.configure(auth)
      # Determine locale for current account/session
      # Priority: account preference > session > request param > default
      auth.auth_class_eval do
        def determine_account_locale
          account[:locale] ||
            session[:locale] ||
            request.params['locale'] ||
            I18n.default_locale.to_s
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

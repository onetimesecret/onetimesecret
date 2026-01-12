# lib/onetime/mail/views/password_request.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Password reset request email template.
      #
      # Required data:
      #   email_address: User's email address
      #
      # One of the following is required:
      #   reset_password_path: Full reset URL (full mode - from Rodauth)
      #   secret:              Secret object for reset (simple mode)
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class PasswordRequest < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          # Either reset_password_path (full mode) or secret (simple mode) is required
          unless data[:reset_password_path] || data[:secret]
            raise ArgumentError, 'Reset password path or secret required'
          end
        end

        public

        def subject
          EmailTranslations.translate(
            'email.password_request.subject',
            locale: locale,
            display_domain: display_domain,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def forgot_path
          # Full mode: reset_password_path is a full URL from Rodauth
          # Simple mode: generate secret-based path (/forgot/...)
          if data[:reset_password_path]
            # Rodauth provides full URL, return empty so baseuri+forgot_path works
            ''
          else
            secret = data[:secret]
            key    = secret.respond_to?(:identifier) ? secret.identifier : secret.to_s
            "/forgot/#{key}"
          end
        end

        def reset_password_url
          # Full URL for password reset - used directly in templates
          data[:reset_password_path] || "#{baseuri}#{forgot_path}"
        end

        def email_address
          data[:email_address]
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            forgot_path: forgot_path,
            reset_password_url: reset_password_url,
            email_address: email_address,
            baseuri: baseuri,
            product_name: product_name,
            display_domain: display_domain,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

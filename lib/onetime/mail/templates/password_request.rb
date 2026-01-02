# lib/onetime/mail/templates/password_request.rb
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
      #   secret:        Secret object containing reset token
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class PasswordRequest < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Secret required' unless data[:secret]
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
          secret = data[:secret]
          # Use identifier (not deprecated .key field which may be nil)
          key = secret.respond_to?(:identifier) ? secret.identifier : secret.to_s
          "/forgot/#{key}"
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

# lib/onetime/mail/templates/welcome.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Welcome/verification email template for new users.
      #
      # Required data:
      #   email_address: User's email address
      #
      # One of the following is required:
      #   verification_path: Full verification URL (full mode - from Rodauth)
      #   secret:            Secret object for verification (simple mode)
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class Welcome < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          # Either verification_path (full mode) or secret (simple mode) is required
          unless data[:verification_path] || data[:secret]
            raise ArgumentError, 'Verification path or secret required'
          end
        end

        public

        def subject
          EmailTranslations.translate(
            'email.welcome.subject',
            locale: locale,
            product_name: product_name,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def verify_uri
          # Full mode: verification_path is a full URL from Rodauth
          # Simple mode: generate secret-based path (/secret/...)
          if data[:verification_path]
            # Rodauth provides full URL, return empty so baseuri+verify_uri works
            ''
          else
            secret = data[:secret]
            key    = secret.respond_to?(:identifier) ? secret.identifier : secret.to_s
            "/secret/#{key}"
          end
        end

        def verification_url
          # Full URL for verification - used directly in templates
          if data[:verification_path]
            data[:verification_path]
          else
            "#{baseuri}#{verify_uri}"
          end
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
            verify_uri: verify_uri,
            verification_url: verification_url,
            email_address: email_address,
            baseuri: baseuri,
            product_name: product_name,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

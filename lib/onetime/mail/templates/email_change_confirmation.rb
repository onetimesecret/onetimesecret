# lib/onetime/mail/templates/email_change_confirmation.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Verification email sent to NEW email address for confirmation.
      #
      # Required data:
      #   new_email:          New email address (recipient)
      #   confirmation_token: Secure token for verification
      #
      # Optional data:
      #   expires_in_hours: Hours until token expires (default: 24)
      #   baseuri:          Override site base URI
      #
      class EmailChangeConfirmation < Base
        DEFAULT_EXPIRY_HOURS = 24

        protected

        def validate_data!
          raise ArgumentError, 'New email required' unless data[:new_email]
          raise ArgumentError, 'Confirmation token required' unless data[:confirmation_token]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.email_change_confirmation.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:new_email]
        end

        def new_email
          data[:new_email]
        end

        def confirmation_token
          data[:confirmation_token]
        end

        def confirmation_uri
          "#{baseuri}/account/email/confirm/#{confirmation_token}"
        end

        def expires_in_hours
          data[:expires_in_hours] || DEFAULT_EXPIRY_HOURS
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            new_email: new_email,
            confirmation_token: confirmation_token,
            confirmation_uri: confirmation_uri,
            expires_in_hours: expires_in_hours,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

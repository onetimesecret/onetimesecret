# lib/onetime/mail/views/password_changed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent when a user's password is changed.
      #
      # Required data:
      #   email_address:  Account email address
      #   changed_at:     ISO8601 timestamp of password change
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class PasswordChanged < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Changed at timestamp required' unless data[:changed_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.password_changed.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def changed_at
          data[:changed_at]
        end

        def changed_at_formatted
          time = Time.parse(changed_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          changed_at.to_s
        end

        def security_settings_path
          '/account/settings/profile/security'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            changed_at: changed_at,
            changed_at_formatted: changed_at_formatted,
            security_settings_path: security_settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

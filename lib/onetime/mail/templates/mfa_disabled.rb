# lib/onetime/mail/templates/mfa_disabled.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent when two-factor authentication is disabled.
      #
      # Required data:
      #   email_address: Account email address
      #   disabled_at:   ISO8601 timestamp of MFA disablement
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class MfaDisabled < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Disabled at timestamp required' unless data[:disabled_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.mfa_disabled.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def disabled_at
          data[:disabled_at]
        end

        def disabled_at_formatted
          time = Time.parse(disabled_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          disabled_at.to_s
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
            disabled_at: disabled_at,
            disabled_at_formatted: disabled_at_formatted,
            security_settings_path: security_settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

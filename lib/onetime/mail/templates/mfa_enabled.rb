# lib/onetime/mail/templates/mfa_enabled.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent when two-factor authentication is enabled.
      #
      # Required data:
      #   email_address: Account email address
      #   enabled_at:    ISO8601 timestamp of MFA enablement
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class MfaEnabled < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Enabled at timestamp required' unless data[:enabled_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.mfa_enabled.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def enabled_at
          data[:enabled_at]
        end

        def enabled_at_formatted
          time = Time.parse(enabled_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          enabled_at.to_s
        end

        def security_settings_path
          '/account/settings/profile/security'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def site_ssl?
          return true unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'ssl') != false
        end

        def site_host
          return 'onetimesecret.com' unless defined?(OT) && OT.respond_to?(:conf)

          OT.conf.dig('site', 'host') || 'onetimesecret.com'
        end

        def site_baseuri
          scheme = site_ssl? ? 'https://' : 'http://'
          "#{scheme}#{site_host}"
        end

        def template_binding
          computed_data = data.merge(
            enabled_at: enabled_at,
            enabled_at_formatted: enabled_at_formatted,
            security_settings_path: security_settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

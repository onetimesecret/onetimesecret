# lib/onetime/mail/templates/new_login_alert.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security alert sent when a new sign-in is detected.
      #
      # Required data:
      #   email_address: Account email address
      #   device_info:   Device/browser information
      #   location:      Geographic location (city, country or IP)
      #   login_at:      ISO8601 timestamp of login
      #
      # Optional data:
      #   ip_address: IP address of login
      #   baseuri:    Override site base URI
      #
      class NewLoginAlert < Base
        protected

        def validate_data!
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Device info required' unless data[:device_info]
          raise ArgumentError, 'Location required' unless data[:location]
          raise ArgumentError, 'Login at timestamp required' unless data[:login_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.new_login_alert.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def device_info
          data[:device_info]
        end

        def location
          data[:location]
        end

        def ip_address
          data[:ip_address]
        end

        def login_at
          data[:login_at]
        end

        def login_at_formatted
          time = Time.parse(login_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          login_at.to_s
        end

        def security_settings_path
          '/account/settings/profile/security'
        end

        def support_path
          '/support'
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
            device_info: device_info,
            location: location,
            ip_address: ip_address,
            login_at: login_at,
            login_at_formatted: login_at_formatted,
            security_settings_path: security_settings_path,
            support_path: support_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

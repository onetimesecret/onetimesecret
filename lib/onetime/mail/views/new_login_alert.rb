# lib/onetime/mail/views/new_login_alert.rb
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
            display_domain: display_domain,
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
          parsed_login_at&.strftime('%B %d, %Y at %H:%M UTC') || login_at.to_s
        end

        # Calendar date of the sign-in, e.g. "January 15, 2024". Split from
        # the time so email.new_login_alert.body can interpolate %{date} and
        # %{time} separately; falls back to the raw value when unparseable.
        def login_at_date
          parsed_login_at&.strftime('%B %d, %Y') || login_at.to_s
        end

        # Wall-clock time of the sign-in, e.g. "10:30 UTC". Empty when the
        # timestamp can't be parsed so the body copy degrades gracefully.
        def login_at_time
          parsed_login_at&.strftime('%H:%M UTC') || ''
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

        # Parsed sign-in timestamp, or nil when the value isn't a valid time.
        # Memoized so the formatted/date/time helpers parse only once.
        def parsed_login_at
          return @parsed_login_at if defined?(@parsed_login_at)

          @parsed_login_at = Time.parse(login_at.to_s)
        rescue ArgumentError
          @parsed_login_at = nil
        end

        def template_binding
          computed_data = data.merge(
            device_info: device_info,
            location: location,
            ip_address: ip_address,
            login_at: login_at,
            login_at_formatted: login_at_formatted,
            login_at_date: login_at_date,
            login_at_time: login_at_time,
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

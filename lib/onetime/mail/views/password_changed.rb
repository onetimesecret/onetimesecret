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
            display_domain: display_domain,
          )
        end

        def recipient_email
          data[:email_address]
        end

        def changed_at
          data[:changed_at]
        end

        def changed_at_formatted
          parsed_changed_at&.strftime('%B %d, %Y at %H:%M UTC') || changed_at.to_s
        end

        # Calendar date of the change, e.g. "January 15, 2024". Split from the
        # time so email.password_changed.body can interpolate %{date} and
        # %{time} separately; falls back to the raw value when unparseable.
        def changed_at_date
          parsed_changed_at&.strftime('%B %d, %Y') || changed_at.to_s
        end

        # Wall-clock time of the change, e.g. "10:30 UTC". Empty when the
        # timestamp can't be parsed so the body copy degrades gracefully.
        def changed_at_time
          parsed_changed_at&.strftime('%H:%M UTC') || ''
        end

        def security_settings_path
          '/account/settings/profile/security'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        # Parsed change timestamp, or nil when the value isn't a valid time.
        # Memoized so the formatted/date/time helpers parse only once.
        def parsed_changed_at
          return @parsed_changed_at if defined?(@parsed_changed_at)

          @parsed_changed_at = Time.parse(changed_at.to_s)
        rescue ArgumentError
          @parsed_changed_at = nil
        end

        def template_binding
          computed_data = data.merge(
            changed_at: changed_at,
            changed_at_formatted: changed_at_formatted,
            changed_at_date: changed_at_date,
            changed_at_time: changed_at_time,
            security_settings_path: security_settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

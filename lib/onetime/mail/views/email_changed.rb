# lib/onetime/mail/views/email_changed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent to OLD email after an email change is confirmed.
      # This is a confirmation-time notification (the email HAS been changed).
      #
      # The full new email address is shown (not obfuscated) because the
      # recipient is the legitimate account owner who needs to see exactly
      # what address the change targets to assess whether it is legitimate.
      #
      # Required data:
      #   old_email:  Previous email address (recipient)
      #   new_email:  Full new email address
      #
      # Optional data:
      #   changed_at: ISO8601 timestamp of the confirmed change
      #   baseuri:    Override site base URI
      #
      class EmailChanged < Base
        protected

        def validate_data!
          raise ArgumentError, 'Old email required' unless data[:old_email]
          raise ArgumentError, 'New email required' unless data[:new_email]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.email_changed.subject',
            locale: locale,
            display_domain: display_domain,
          )
        end

        def recipient_email
          data[:old_email]
        end

        def old_email
          data[:old_email]
        end

        def new_email
          data[:new_email]
        end

        def changed_at
          data[:changed_at] || Time.now.utc.iso8601
        end

        def changed_at_formatted
          time = Time.parse(changed_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          changed_at.to_s
        end

        def support_path
          '/feedback?reason=email_change_unauthorized'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            old_email: old_email,
            new_email: new_email,
            changed_at: changed_at,
            changed_at_formatted: changed_at_formatted,
            support_path: support_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

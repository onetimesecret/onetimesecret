# lib/onetime/mail/views/email_change_requested.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent to OLD email when an email change is requested.
      # This is a request-time notification (the email has NOT changed yet).
      #
      # The full new email address is shown (not obfuscated) because the
      # recipient is the legitimate account owner who needs to see exactly
      # what address the change targets to assess whether it is legitimate.
      #
      # Required data:
      #   old_email:  Current email address (recipient)
      #   new_email:  Full new email address
      #
      # Optional data:
      #   requested_at: ISO8601 timestamp of the request
      #   baseuri:      Override site base URI
      #
      class EmailChangeRequested < Base
        protected

        def validate_data!
          raise ArgumentError, 'Old email required' unless data[:old_email]
          raise ArgumentError, 'New email required' unless data[:new_email]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.email_change_requested.subject',
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

        def requested_at
          data[:requested_at] || Time.now.utc.iso8601
        end

        def requested_at_formatted
          time = Time.parse(requested_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          requested_at.to_s
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
            requested_at: requested_at,
            requested_at_formatted: requested_at_formatted,
            support_path: support_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

# lib/onetime/mail/templates/email_changed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Security notification sent to OLD email when email address is changed.
      #
      # Required data:
      #   old_email:        Previous email address (recipient)
      #   new_email_masked: Masked new email (e.g., "j***@example.com")
      #
      # Optional data:
      #   changed_at: ISO8601 timestamp of email change
      #   baseuri:    Override site base URI
      #
      class EmailChanged < Base
        protected

        def validate_data!
          raise ArgumentError, 'Old email required' unless data[:old_email]
          raise ArgumentError, 'Masked new email required' unless data[:new_email_masked]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.email_changed.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:old_email]
        end

        def old_email
          data[:old_email]
        end

        def new_email_masked
          data[:new_email_masked]
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
            old_email: old_email,
            new_email_masked: new_email_masked,
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

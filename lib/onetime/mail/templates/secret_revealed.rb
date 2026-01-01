# lib/onetime/mail/templates/secret_revealed.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Notification email sent to secret owner when their secret is revealed.
      #
      # Required data:
      #   recipient:       Owner's email address
      #   secret_shortid:  Short identifier of the revealed secret
      #   revealed_at:     ISO8601 timestamp of reveal
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      class SecretRevealed < Base
        protected

        def validate_data!
          raise ArgumentError, 'Recipient email required' unless data[:recipient]
          raise ArgumentError, 'Secret shortid required' unless data[:secret_shortid]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.secret_revealed.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:recipient]
        end

        def secret_shortid
          data[:secret_shortid]
        end

        def revealed_at
          data[:revealed_at] || Time.now.utc.iso8601
        end

        def revealed_at_formatted
          time = Time.parse(revealed_at.to_s)
          time.strftime('%B %d, %Y at %H:%M UTC')
        rescue ArgumentError
          revealed_at.to_s
        end

        def settings_path
          '/account/settings/profile/notifications'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def template_binding
          computed_data = data.merge(
            secret_shortid: secret_shortid,
            revealed_at: revealed_at,
            revealed_at_formatted: revealed_at_formatted,
            settings_path: settings_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

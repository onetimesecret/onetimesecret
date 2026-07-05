# lib/onetime/mail/views/incoming_secret.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email notification for incoming secrets feature.
      # Sent to configured recipients when someone submits a secret via /incoming.
      #
      # Required data:
      #   secret_key:   Secret key for URL (string)
      #   recipient:    Recipient email address
      #
      # Optional data:
      #   share_domain: Custom domain for secret sharing
      #   memo:         Brief description from sender (shown in body, not subject for security)
      #   baseuri:      Override site base URI
      #
      # NOTE: Uses primitive data types for RabbitMQ serialization.
      # Secret objects cannot be serialized to JSON.
      #
      class IncomingSecret < Base
        protected

        def validate_data!
          raise ArgumentError, 'Secret key required' unless data[:secret_key]
          raise ArgumentError, 'Recipient required' unless data[:recipient]
        end

        public

        def subject
          # Security: Don't include memo in subject - visible in email list views
          EmailTranslations.translate(
            'email.incoming_secret.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:recipient]
        end

        def uri_path
          "/secret/#{data[:secret_key]}"
        end

        def memo
          data[:memo]
        end

        def has_memo?
          !memo.to_s.empty?
        end

        def signature_link
          site_baseuri
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        def has_passphrase?
          data[:has_passphrase] == true
        end

        # The secret link itself is built in the template from brand_baseuri
        # (a TemplateContext helper reading share_domain) plus uri_path.
        def template_binding
          computed_data = data.merge(
            uri_path: uri_path,
            memo: memo,
            has_memo: has_memo?,
            has_passphrase: has_passphrase?,
            signature_link: signature_link,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

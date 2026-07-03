# lib/onetime/mail/views/secret_link.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for sharing a secret link with a recipient.
      #
      # Required data:
      #   secret_key:   Secret key for URL (string)
      #   recipient:    Recipient email address
      #   sender_email: Sender's email address (shown in email body)
      #
      # Optional data:
      #   share_domain: Custom domain for secret sharing
      #   baseuri:      Override site base URI
      #
      # NOTE: Uses primitive data types for RabbitMQ serialization.
      # Secret objects cannot be serialized to JSON.
      #
      class SecretLink < Base
        protected

        def validate_data!
          raise ArgumentError, 'Secret key required' unless data[:secret_key]
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          raise ArgumentError, 'Sender email required' unless data[:sender_email]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.secret_link.subject',
            locale: locale,
            sender_email: data[:sender_email],
          )
        end

        def recipient_email
          data[:recipient]
        end

        def uri_path
          "/secret/#{data[:secret_key]}"
        end

        def custid
          data[:sender_email]
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

        # Override to include computed values in template context.
        # The secret link itself is built in the template from brand_baseuri
        # (a TemplateContext helper reading share_domain) plus uri_path.
        def template_binding
          computed_data = data.merge(
            uri_path: uri_path,
            custid: custid,
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

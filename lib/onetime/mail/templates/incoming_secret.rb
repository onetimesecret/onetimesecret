# lib/onetime/mail/templates/incoming_secret.rb
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
      #   secret:    Secret object with #key method
      #   recipient: Recipient email address
      #
      # Optional data:
      #   memo:    Brief description from sender (shown in body, not subject for security)
      #   baseuri: Override site base URI
      #
      class IncomingSecret < Base
        protected

        def validate_data!
          raise ArgumentError, 'Secret required' unless data[:secret]
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

        def display_domain
          secret = data[:secret]
          scheme = site_ssl? ? 'https://' : 'http://'
          host   = (secret.respond_to?(:share_domain) && secret.share_domain) || site_host
          "#{scheme}#{host}"
        end

        def uri_path
          secret = data[:secret]
          key    = secret.respond_to?(:key) ? secret.key : secret.to_s
          "/secret/#{key}"
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

        def template_binding
          computed_data = data.merge(
            display_domain: display_domain,
            uri_path: uri_path,
            memo: memo,
            has_memo: has_memo?,
            signature_link: signature_link,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

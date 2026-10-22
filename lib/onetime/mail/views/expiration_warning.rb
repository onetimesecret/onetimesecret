# lib/onetime/mail/views/expiration_warning.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for warning a secret's owner that it is about to expire.
      #
      # The link is the owner's receipt page, /receipt/<receipt identifier>,
      # where the owner sees whether the secret has been viewed and can burn
      # it. It is not the secret link: the owner is not meant to consume their
      # own secret. The previous payload carried the secret's 8-character short
      # id under :secret_key and the template built /secret/<short id>, which
      # no route resolves, so every link in every warning was dead.
      #
      # Required data:
      #   recipient:          Owner's email address
      #   receipt_identifier: Full receipt identifier (Receipt#identifier)
      #   expires_at:         Unix timestamp when the secret expires
      #
      # Optional data:
      #   share_domain: Custom domain the secret was shared from
      #   baseuri:      Override site base URI
      #
      # A payload without receipt_identifier (one queued by the previous job
      # version) fails validate_data! with an ArgumentError. EmailWorker does
      # not retry an ArgumentError: the message is rejected to the DLQ as
      # invalid_message, so a dead link is never sent.
      #
      class ExpirationWarning < Base
        protected

        def validate_data!
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          raise ArgumentError, 'Receipt identifier required' if data[:receipt_identifier].to_s.strip.empty?
          raise ArgumentError, 'Expiration time required' unless data[:expires_at]
        end

        public

        def subject
          EmailTranslations.translate(
            'email.expiration_warning.subject',
            locale: locale,
          )
        end

        def recipient_email
          data[:recipient]
        end

        # Computed template variables

        # Human-readable time remaining until expiration
        def time_remaining
          seconds = data[:expires_at].to_i - Time.now.to_i
          return 'soon' if seconds <= 0

          if seconds < 3600
            minutes = (seconds / 60.0).ceil
            "#{minutes} minute#{'s' if minutes != 1}"
          elsif seconds < 86_400
            hours = (seconds / 3600.0).ceil
            "#{hours} hour#{'s' if hours != 1}"
          else
            days = (seconds / 86_400.0).ceil
            "#{days} day#{'s' if days != 1}"
          end
        end

        def uri_path
          "/receipt/#{data[:receipt_identifier]}"
        end

        # Full URI of the owner's receipt page, on the domain the secret was
        # shared from (share_domain when present, canonical host otherwise),
        # as the receipt endpoints build receipt_url.
        def receipt_uri
          "#{brand_baseuri}#{uri_path}"
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        # Override to include computed values in template context
        def template_binding
          computed_data = data.merge(
            time_remaining: time_remaining,
            receipt_uri: receipt_uri,
            uri_path: uri_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

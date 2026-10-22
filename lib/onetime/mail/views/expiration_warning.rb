# lib/onetime/mail/views/expiration_warning.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for warning users that their secret is about to expire.
      #
      # Links to the owner's receipt page, not to the secret. The receipt page
      # applies the provenance gate (Receipt#shows_share_link?) before showing
      # the share link, and the email keeps the secret identifier out of the
      # owner's inbox.
      #
      # Required data:
      #   recipient:          Recipient email address (secret owner)
      #   receipt_identifier: Full receipt identifier for the receipt URL
      #   expires_at:         Unix timestamp when secret expires
      #
      # Optional data:
      #   share_domain: Custom domain for secret sharing
      #   baseuri:      Override site base URI
      #
      class ExpirationWarning < Base
        protected

        def validate_data!
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          # Payloads queued before the receipt link carry only secret_key (a
          # secret shortid), which resolves to no page. They fail here so the
          # email worker drops them instead of sending a dead link.
          raise ArgumentError, 'Receipt identifier required' if data[:receipt_identifier].to_s.empty?
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

        # Full URI to the owner's receipt page, on the domain the secret was
        # shared from (share_domain when present, canonical host otherwise).
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

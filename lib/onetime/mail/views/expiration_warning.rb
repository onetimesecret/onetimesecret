# lib/onetime/mail/views/expiration_warning.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for warning users that their secret is about to expire.
      #
      # Required data:
      #   recipient:    Recipient email address (secret owner)
      #   secret_key:   Secret shortid for URL
      #   expires_at:   Unix timestamp when secret expires
      #
      # Optional data:
      #   share_domain: Custom domain for secret sharing
      #   baseuri:      Override site base URI
      #
      class ExpirationWarning < Base
        protected

        def validate_data!
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          raise ArgumentError, 'Secret key required' unless data[:secret_key]
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
          "/secret/#{data[:secret_key]}"
        end

        # Full URI to view the secret, on the domain the secret was shared
        # from (share_domain when present, canonical host otherwise).
        def secret_uri
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
            secret_uri: secret_uri,
            uri_path: uri_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

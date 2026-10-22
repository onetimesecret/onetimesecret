# lib/onetime/mail/views/expiration_warning.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for warning a secret's owner that it is about to expire.
      #
      # An account notification, like SecretRevealed: it names the secret by
      # its short id and links to the owner's recent-secrets page, /recent,
      # on the canonical host. That page requires a session. The email
      # carries no identifier that resolves anything: /receipt/<identifier>
      # and /secret/<identifier> are bearer capabilities (the receipt route
      # answers without an ownership check and returns the share link), and
      # a mailbox is not a place to keep one.
      #
      # The previous payload carried the secret's short id under :secret_key
      # and the template built /secret/<short id>. That path serves the page
      # shell (GET /secret/* in apps/web/core/routes.txt), but the lookup
      # behind it fails: an 8-character prefix is not a secret identifier. So
      # every link in every warning led to a not-found page.
      #
      # Required data:
      #   recipient:      Owner's email address
      #   secret_shortid: Secret#shortid, the 8-character prefix the receipt
      #                   page shows the owner
      #   expires_at:     Unix timestamp when the secret expires
      #
      # Optional data:
      #   baseuri: Override site base URI
      #
      # A payload without secret_shortid (one queued by the previous job
      # version) fails validate_data! with an ArgumentError. EmailWorker does
      # not retry an ArgumentError: the message is rejected to the DLQ as
      # invalid_message instead of being sent with the dead link.
      #
      class ExpirationWarning < Base
        protected

        def validate_data!
          raise ArgumentError, 'Recipient required' unless data[:recipient]
          raise ArgumentError, 'Secret short id required' if data[:secret_shortid].to_s.strip.empty?
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

        def secret_shortid
          data[:secret_shortid]
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

        # The owner's recent-secrets page (web route: auth=sessionauth).
        def uri_path
          '/recent'
        end

        # Full URI of the recent-secrets page. Built from baseuri, the
        # canonical host, as other install-level paths in mail are; the
        # domain a secret was shared from plays no part in where its owner
        # signs in.
        def recent_uri
          "#{baseuri}#{uri_path}"
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        private

        # Override to include computed values in template context
        def template_binding
          computed_data = data.merge(
            time_remaining: time_remaining,
            secret_shortid: secret_shortid,
            recent_uri: recent_uri,
            uri_path: uri_path,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

# lib/onetime/mail/views/feedback_email.rb
#
# frozen_string_literal: true

require_relative 'base'

module Onetime
  module Mail
    module Templates
      # Email template for user feedback submissions.
      # Sent to administrators when a user submits feedback via /feedback.
      #
      # Required data:
      #   recipient_email:  Admin/colonel email to receive the feedback
      #   email_address:    Sender's email address (feedback submitter, or 'anonymous')
      #   message:          Feedback message content
      #   display_domain:   Domain where feedback was submitted
      #
      # Optional data:
      #   domain_strategy:  How the domain was determined (e.g., 'custom', 'default')
      #   baseuri:          Override site base URI
      #   user_id:          Submitter identifier (extid / 'anon:NNNN'); rendered
      #                     in the body alongside the obscured email
      #   tz:               Submitter timezone string
      #   version:          Client version string
      #
      class FeedbackEmail < Base
        # Placeholder rendered when an optional metadata field is absent.
        # Older queued jobs and minimal test fixtures may not supply
        # user_id/tz/version, but the templates reference them unconditionally.
        UNKNOWN_VALUE = '-'

        protected

        def validate_data!
          raise ArgumentError, 'Recipient email required' unless data[:recipient_email]
          raise ArgumentError, 'Email address required' unless data[:email_address]
          raise ArgumentError, 'Message required' unless data[:message]
          raise ArgumentError, 'Display domain required' unless data[:display_domain]
        end

        public

        def subject
          stamp    = Time.now.utc.strftime('%b %d, %Y')
          strategy = data[:domain_strategy] || 'default'
          EmailTranslations.translate(
            'email.feedback_email.subject',
            locale: locale,
            date: stamp,
            display_domain: data[:display_domain],
            strategy: strategy,
          )
        end

        # The admin/colonel who receives the feedback email
        def recipient_email
          data[:recipient_email]
        end

        # The user who submitted the feedback (shown in email body)
        def sender_email
          data[:email_address]
        end

        def message
          data[:message]
        end

        def display_domain
          data[:display_domain]
        end

        def domain_strategy
          data[:domain_strategy] || 'default'
        end

        def baseuri
          data[:baseuri] || site_baseuri
        end

        def user_id
          fetch_optional(:user_id)
        end

        def timezone
          fetch_optional(:tz)
        end

        def client_version
          fetch_optional(:version)
        end

        private

        # Optional metadata may arrive as symbol keys (in-process callers) or
        # string keys (deserialized from the email job queue). Either is fine;
        # a missing value falls back to UNKNOWN_VALUE so rendering stays valid.
        def fetch_optional(key)
          value = data[key] || data[key.to_s]
          value.nil? || value.to_s.empty? ? UNKNOWN_VALUE : value
        end

        def template_binding
          computed_data = data.merge(
            email_address: sender_email,
            message: message,
            display_domain: display_domain,
            domain_strategy: domain_strategy,
            baseuri: baseuri,
            user_id: user_id,
            tz: timezone,
            version: client_version,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

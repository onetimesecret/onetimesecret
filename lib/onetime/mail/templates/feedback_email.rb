# lib/onetime/mail/templates/feedback_email.rb
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
      #   email_address:    Sender's email address (feedback submitter)
      #   message:          Feedback message content
      #   display_domain:   Domain where feedback was submitted
      #
      # Optional data:
      #   domain_strategy:  How the domain was determined (e.g., 'custom', 'default')
      #   baseuri:          Override site base URI
      #
      class FeedbackEmail < Base
        protected

        def validate_data!
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

        def recipient_email
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

        private

        def template_binding
          computed_data = data.merge(
            message: message,
            display_domain: display_domain,
            domain_strategy: domain_strategy,
            baseuri: baseuri,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

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
      #   user_id:          Submitter identifier (extid / 'anon:NNNN'); rendered
      #                     in the body alongside the obscured email
      #   customer_extid:   Submitter's PUBLIC id, authenticated submitters only.
      #                     Rendered as a link to their colonel customer page.
      #   organization_extids: PUBLIC ids of the submitter's organizations
      #                     (authenticated submitters only), each rendered as
      #                     a link to its colonel organization page.
      #   tz:               Submitter timezone string
      #   version:          Client version string
      #   baseuri:          Override site base URI
      #
      class FeedbackEmail < Base
        # Do not wrap the plaintext body in the shared text layout. This email
        # is operator-facing — it is sent FROM a user TO the operators who *are*
        # support — so appending a "Support: <address>" line is nonsensical, and
        # its own trailing block is a signature sign-off, not the product
        # footer. Wrapping it would also double-print a footer. See #3362.
        text_layout false

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

        # Submitter identifier shown in the email body. Falls back to UNKNOWN_VALUE
        # so the template never sees a nil/missing local.
        def user_id
          fetch_optional(:user_id)
        end

        def tz
          fetch_optional(:tz)
        end

        def version
          fetch_optional(:version)
        end

        # The submitter's PUBLIC id, or nil for anonymous feedback (and for
        # jobs queued before this field existed).
        def customer_extid
          value = data[:customer_extid] || data['customer_extid']
          value.to_s.empty? ? nil : value.to_s
        end

        # Colonel customer page for the submitter, or nil when anonymous.
        def colonel_customer_url
          customer_extid && colonel_url('customers', customer_extid)
        end

        # The submitter's organizations as `{ extid:, url: }` pairs, url being
        # the colonel organization page. Empty for anonymous feedback.
        def organizations
          extids = data[:organization_extids] || data['organization_extids']
          Array(extids).map(&:to_s).reject(&:empty?).map do |extid|
            { extid: extid, url: colonel_url('organizations', extid) }
          end
        end

        private

        # Links into the colonel console go to the canonical site host: the
        # console's host gate admits the canonical anchors by default, and a
        # tenant custom domain (the feedback's display_domain) never serves it.
        # Only PUBLIC ids go into these URLs; they end up in mail archives and
        # browser history.
        def colonel_url(section, extid)
          "#{site_baseuri}/colonel/#{section}/#{ERB::Util.url_encode(extid)}"
        end

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
            tz: tz,
            version: version,
            colonel_customer_url: colonel_customer_url,
            organizations: organizations,
          )
          TemplateContext.new(computed_data, locale).get_binding
        end
      end
    end
  end
end

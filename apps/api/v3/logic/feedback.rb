# apps/api/v3/logic/feedback.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../../../../lib/onetime/jobs/publisher'

module V3
  module Logic
    # @api Submit a feedback message. Accepts a text message with
    #   optional timezone and client version metadata. Available to
    #   both authenticated and anonymous users.
    #
    # Rate limiting: 10 requests per hour per IP to prevent abuse.
    # This prevents email storms to colonels and feedback store flooding.
    class ReceiveFeedback < V3::Logic::Base
      SCHEMAS = { response: 'feedback' }.freeze

      # Rate limit: 10 feedback submissions per hour per IP
      # Generous enough for legitimate use, restrictive enough to prevent abuse
      FEEDBACK_RATE_LIMIT_MAX    = 10
      FEEDBACK_RATE_LIMIT_WINDOW = 3600 # 1 hour

      # Frontend forms (FeedbackForm.vue, FeedbackModalForm.vue) mirror this
      # value via their local MAX_MSG_LENGTH constant so users see a counter
      # and maxlength warning before the server silently truncates oversized
      # messages. Keep these in sync.
      MAX_MSG_LENGTH     = 200_000 # Generous upper bound; UI surfaces it to users
      MAX_TZ_LENGTH      = 64
      MAX_VERSION_LENGTH = 32

      attr_reader :msg, :greenlighted, :tz, :version

      def process_params
        @msg     = sanitize_plain_text(params['msg'], max_length: MAX_MSG_LENGTH)
        @tz      = sanitize_plain_text(params['tz'], max_length: MAX_TZ_LENGTH)
        @version = sanitize_plain_text(params['version'], max_length: MAX_VERSION_LENGTH)
      end

      def raise_concerns
        raise_form_error 'You can be more original than that!' if @msg.empty?
      end

      def process
        @greenlighted = true
        @msg          = format_feedback_message
        OT.ld [:receive_feedback, msg].inspect

        begin
          # Resolve the recipient. An explicit emailer.feedback_to override
          # (env: FEEDBACK_TO_EMAIL) wins; otherwise fall back to the first
          # colonel in the database.
          # Colonels are managed via CLI: bin/ots customers role promote email --role colonel
          recipient_email = feedback_recipient_email
          if recipient_email
            OT.ld "[receive_feedback] Sending feedback to: #{recipient_email}"
            send_feedback recipient_email, cust, msg
          else
            OT.ld '[receive_feedback] No feedback recipient configured and no colonels found, skipping email notification'
          end
        rescue StandardError => ex
          # We liberally rescue all StandardError exceptions here because we don't
          # want to fail the user's feedback submission if we can't send an email.
          OT.le "Error sending feedback email: #{ex.message}", ex.backtrace
        end

        Onetime::Feedback.add @msg

        success_data
      end

      def format_feedback_message
        # Use extid for authenticated users, session-based identifier for anonymous.
        # anonymous_user? is from AuthorizationPolicies, checks cust.nil? || cust.anonymous?
        identifier = if anonymous_user?
                       # Generate short identifier from session for anonymous users
                       sess_id = sess.respond_to?(:id) ? sess.id&.public_id : sess.object_id.to_s(16)
                       "anon:#{sess_id.to_s[0, 8]}"
                     else
                       cust.extid
                     end
        "#{msg} [#{identifier}] [TZ: #{tz}] [v#{version}]"
      end
      private :format_feedback_message

      def success_data
        {
          record: {},
          details: {
            message: 'Message received. Send as much as you like!',
          },
        }
      end

      def send_feedback(recipient_email, sender, message)
        OT.ld "[send_feedback] Delivering feedback email (#{message.size} chars)"

        # Logic classes don't receive req.env, so display_domain may be nil.
        # Fall back to site host from config for feedback emails.
        effective_domain = display_domain || OT.conf.dig('site', 'host')

        # Determine sender email - use actual email for authenticated users,
        # 'anonymous' indicator for guests (nil sender or anonymous flag)
        is_anonymous = sender.nil? || sender.anonymous?
        sender_email = is_anonymous ? 'anonymous' : sender.email

        email_data = {
          recipient_email: recipient_email,
          email_address: sender_email,
          message: message,
          display_domain: effective_domain,
          domain_strategy: domain_strategy || :default,
          locale: locale || OT.default_locale,
        }

        # When the submitter is authenticated, set Reply-To to their email so
        # admins can reply directly without copy/pasting from the message body.
        # For anonymous submissions reply_to is omitted so the mailer falls
        # back to the configured from address (no inbox to reply to).
        email_data[:reply_to] = sender.email unless is_anonymous

        begin
          # Non-critical: feedback is saved in Redis regardless of email
          # Use :none fallback - don't block or spawn threads for notifications
          Onetime::Jobs::Publisher.enqueue_email(
            :feedback_email,
            email_data,
            fallback: :none,
          )
        rescue StandardError => ex
          OT.le "Error sending feedback email: #{ex.message}", ex.backtrace
          # No need to notify the user of this error. The message is still
          # saved in Redis and available via the colonel interface.
        end
      end

      # Resolve the To: address for feedback emails.
      #
      # Precedence:
      #   1. emailer.feedback_to in OT.conf (env: FEEDBACK_TO_EMAIL) — explicit
      #      override, useful when feedback should land in a shared inbox
      #      rather than chasing whichever colonel happens to be first.
      #   2. The first colonel's email (legacy fallback for self-hosted setups
      #      that haven't configured an override).
      #   3. nil — no recipient available; the email step is skipped.
      def feedback_recipient_email
        configured = OT.conf.dig('emailer', 'feedback_to')
        return configured if configured.is_a?(String) && !configured.strip.empty?

        find_first_colonel&.email
      end
      private :feedback_recipient_email

      # Find the first colonel in the database
      # Returns nil if no colonels exist
      # Delegates to Customer.find_first_colonel which uses multi_index
      # for O(1) lookup instead of O(n) scanning all customers.
      def find_first_colonel
        Onetime::Customer.find_first_colonel
      end
      private :find_first_colonel
    end
  end
end

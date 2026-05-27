# apps/api/v3/logic/feedback.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../../../../lib/onetime/jobs/publisher'
require 'onetime/security/feedback_rate_limiter'

module V3
  module Logic
    # @api Submit a feedback message. Accepts a text message with
    #   optional timezone and client version metadata. Available to
    #   both authenticated and anonymous users.
    #
    # Rate limiting is enforced via Onetime::Security::FeedbackRateLimiter,
    # which tracks per-IP submissions in Redis and locks abusers out for
    # an hour after exceeding the threshold.
    class ReceiveFeedback < V3::Logic::Base
      include Onetime::Security::FeedbackRateLimiter

      SCHEMAS = { response: 'feedback' }.freeze

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
        check_feedback_rate_limit!(client_ip)
        raise_form_error 'You can be more original than that!' if @msg.empty?
      end

      def process
        @greenlighted = true
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

        # Stored Redis copy keeps the metadata appended on a single line so the
        # colonel admin view can read submitter / TZ / version without a join.
        Onetime::Feedback.add formatted_for_storage(msg)

        # Count this submission for rate-limit accounting. Recording after
        # storage means failed validation / empty messages don't burn quota.
        record_feedback_submission!(client_ip)

        success_data
      end

      # Resolve the submitter's IP from the auth strategy metadata.
      # Logic classes don't receive the Rack request directly; the auth
      # strategies populate strategy_result.metadata[:ip] (see
      # apps/web/auth/spec/unit/*_strategy_spec.rb). A few callers use
      # :ip_address instead, so we accept both. Returns nil if neither is
      # present — the rate limiter treats blank IPs as a no-op.
      def client_ip
        meta = strategy_result&.metadata
        return nil unless meta

        meta[:ip] || meta[:ip_address] || meta['ip'] || meta['ip_address']
      end
      private :client_ip

      # Identifier for the submitter. Authenticated users get their extid;
      # anonymous users get a stable-per-session anon prefix.
      def feedback_user_id
        if anonymous_user?
          sess_id = sess.respond_to?(:id) ? sess.id&.public_id : sess.object_id.to_s(16)
          "anon:#{sess_id.to_s[0, 8]}"
        else
          cust.extid
        end
      end
      private :feedback_user_id

      def formatted_for_storage(message)
        "#{message} [#{feedback_user_id}] [TZ: #{tz}] [v#{version}]"
      end
      private :formatted_for_storage

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

        # The body shows an obscured form of the submitter's address so a
        # leaked archive doesn't expose verbatim email addresses. The actual
        # address still rides on the Reply-To header (set below) so admins can
        # reply directly.
        is_anonymous = sender.nil? || sender.anonymous?
        display_from = is_anonymous ? 'anonymous' : OT::Utils.obscure_email(sender.email)

        email_data = {
          recipient_email: recipient_email,
          email_address: display_from,
          user_id: feedback_user_id,
          tz: tz,
          version: version,
          message: message,
          display_domain: effective_domain,
          domain_strategy: domain_strategy || :default,
          locale: locale || OT.default_locale,
        }

        # When the submitter is authenticated, set Reply-To to their real email
        # so admins can reply directly without copy/pasting from the body.
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

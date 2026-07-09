# lib/onetime/mail/delivery/base.rb
#
# frozen_string_literal: true

require 'openssl'

module Onetime
  module Mail
    module Delivery
      # Abstract base class for email delivery backends.
      # Subclasses implement provider-specific delivery logic.
      #
      # All backends accept a standardized email hash:
      #   {
      #     to: "recipient@example.com",
      #     from: "sender@example.com",
      #     reply_to: "reply@example.com",  # optional
      #     subject: "Email subject",
      #     text_body: "Plain text content",
      #     html_body: "<html>...</html>"    # optional
      #   }
      #
      class Base
        attr_reader :config

        # Network errors common across all providers
        NETWORK_ERRORS = [
          Errno::ECONNREFUSED,
          Errno::ECONNRESET,
          Errno::ETIMEDOUT,
          Net::OpenTimeout,
          Net::ReadTimeout,
          IOError,
          SocketError,
          OpenSSL::SSL::SSLError,
        ].freeze

        def initialize(config = {})
          @config = config
          validate_config!
        end

        # Deliver an email message with unified error handling.
        # Subclasses implement perform_delivery and classify_error.
        # @param email [Hash] Email parameters (to, from, subject, text_body, html_body)
        # @return [Object] Provider-specific response, or nil when the recipient
        #   is on the suppression list (send skipped, nothing dispatched)
        def deliver(email)
          email = normalize_email(email)

          # Outbound suppression guard: never send to an address with a recorded
          # bounce/complaint — repeat sends to known-bad addresses are what burn
          # sender reputation. One Redis lookup, fail-open (see the helper).
          if suppressed_recipient?(email)
            log_delivery(email, 'suppressed')
            return nil
          end

          result = perform_delivery(email)
          log_delivery(email, delivery_log_status)
          record_sent_metric
          result
        rescue Onetime::Mail::DeliveryError
          raise # pass-through, no double-wrap
        rescue StandardError => ex
          log_error(email, ex)
          record_sync_bounce(email, ex)
          transient = classify_error(ex) == :transient
          raise Onetime::Mail::DeliveryError.new(
            "#{provider_name} delivery error: #{ex.message}",
            original_error: ex,
            transient: transient,
          )
        end

        # Subclass hook: provider-specific send logic
        # @param email [Hash] Normalized email parameters
        # @return [Object] Provider-specific response
        def perform_delivery(email)
          raise NotImplementedError, "#{self.class} must implement #perform_delivery"
        end

        # Subclass hook: classify provider-specific errors.
        # Returns :transient, :fatal, or :unknown.
        # :unknown defaults to non-transient (fail fast).
        # @param error [StandardError] The error to classify
        # @return [Symbol] :transient, :fatal, or :unknown
        def classify_error(error)
          return :transient if NETWORK_ERRORS.any? { |klass| error.is_a?(klass) }

          :unknown
        end

        # Override in subclasses to change the log status label
        # @return [String]
        def delivery_log_status
          'sent'
        end

        # Provider name for logging
        # @return [String]
        def provider_name
          self.class.name.split('::').last
        end

        protected

        # Best-effort global "emails sent" tally, surfaced on the colonel stats
        # dashboard (issue #3653, debt §7 — the send chokepoint for emails_sent).
        #
        # This is the single point every backend's successful send converges on,
        # so the counter is incremented exactly once per delivered email. Only real
        # provider sends count: the Disabled backend reports 'skipped' and the
        # Logger backend reports 'logged' — neither emits an actual email, so they
        # must not inflate the metric.
        #
        # A metrics write must never disrupt mail delivery, so the increment is
        # guarded (Onetime::Customer may be absent in isolated mailer tests) and
        # any error is swallowed.
        def record_sent_metric
          return unless delivery_log_status == 'sent'
          return unless defined?(Onetime::Customer)

          Onetime::Customer.emails_sent.increment
        rescue StandardError => ex
          if defined?(OT) && OT.respond_to?(:le)
            OT.le "[mail] emails_sent counter increment failed: #{ex.message}"
          end
          nil
        end

        # The suppression-list check guarding every send (the deliverability
        # counterpart of record_sent_metric — same single chokepoint, so every
        # backend and every entry point above them is covered).
        #
        # FAIL-OPEN by contract: EmailSuppression.skip_send? already swallows
        # Redis errors, and this wrapper adds a second layer (plus the same
        # defined? guard record_sent_metric uses for isolated mailer tests) so
        # a suppression-check failure can NEVER block mail delivery — losing
        # one skip is a rounding error; blocking all outbound mail is an outage.
        #
        # A send fans out to every recipient in email[:to], so the guard must
        # inspect each mailbox individually: a To of "a@x.com, b@x.com" or an
        # Array of addresses would otherwise be looked up as one opaque string
        # and never match a suppressed mailbox in the set. If ANY recipient is
        # suppressed the whole send is skipped — the backends dispatch to all
        # recipients at once, so there is no way to drop just one without
        # rewriting the message; skipping matches the existing return-nil
        # semantics and keeps known-bad addresses off the wire.
        #
        # @return [Boolean] true when any recipient is suppressed (skip the send)
        def suppressed_recipient?(email)
          return false unless defined?(Onetime::EmailSuppression)

          recipient_mailboxes(email[:to]).any? do |address|
            Onetime::EmailSuppression.skip_send?(address)
          end
        rescue StandardError => ex
          if defined?(OT) && OT.respond_to?(:le)
            OT.le "[mail] suppression check failed (failing open): #{ex.message}"
          end
          false
        end

        # Record a synchronous hard bounce into the deliverability event feed.
        #
        # Deliberately narrow: only SMTP 5xx rejections (Net::SMTPFatalError —
        # e.g. 550 mailbox unavailable) are recipient-level feedback we can
        # trust at send time. Other fatal errors (auth failures, API 4xx,
        # config problems) are SENDER-side and must not show up as bounces.
        # Recording is event-only — no auto-suppression from a single
        # synchronous failure; suppression comes from ESP feedback ingestion
        # or an operator decision (see Onetime::EmailSuppression).
        #
        # Best-effort like record_sent_metric: a feed write must never mask
        # the delivery error being raised to the caller.
        def record_sync_bounce(email, error)
          return unless defined?(Onetime::EmailSuppression)
          return unless defined?(Net::SMTPFatalError) && error.is_a?(Net::SMTPFatalError)

          Onetime::EmailSuppression.record_event(
            address: email[:to],
            kind: 'bounce',
            reason: error.message.to_s,
            source: "#{provider_name.downcase}-sync",
          )
        rescue StandardError => ex
          if defined?(OT) && OT.respond_to?(:le)
            OT.le "[mail] sync bounce recording failed: #{ex.message}"
          end
          nil
        end

        # Override in subclasses for provider-specific validation
        def validate_config!
          # Base implementation does nothing
        end

        def log_delivery(email, status = 'sent')
          obscured = obscure_email(email[:to])
          message  = "[mail] #{status.capitalize} via #{provider_name} to #{obscured}: #{email[:subject]}"
          if defined?(OT) && OT.respond_to?(:info)
            OT.info message
          else
            puts message
          end
        end

        def log_error(email, error)
          obscured = obscure_email(email[:to])
          message  = "[mail] Delivery failed via #{provider_name} to #{obscured}: #{error.message}"
          if defined?(OT) && OT.respond_to?(:le)
            OT.le message
          else
            warn message
          end
        end

        # Obscure email address for logging
        def obscure_email(email)
          return email if email.to_s.empty?

          # Try to use OT::Utils if available
          if defined?(OT::Utils) && OT::Utils.respond_to?(:obscure_email)
            OT::Utils.obscure_email(email)
          else
            # Simple fallback obscuring
            parts          = email.to_s.split('@')
            return email if parts.length != 2

            local          = parts[0]
            domain         = parts[1]
            obscured_local = local.length > 2 ? "#{local[0..1]}***" : '***'
            "#{obscured_local}@#{domain}"
          end
        end

        # Canonicalize the :to field to a string the backends can hand to a
        # provider. An Array of recipients is joined into a comma-separated
        # string (the form every backend already expects); a String passes
        # through unchanged. Keeps any display names intact for the header —
        # mailbox extraction for the suppression guard is handled separately.
        def normalize_recipients(value)
          return value.to_s unless value.is_a?(Array)

          value.map(&:to_s).map(&:strip).reject(&:empty?).join(', ')
        end

        # Split a recipient value into individual mailbox addresses.
        #
        # Handles the shapes a mailer can hand us for :to — an Array of
        # addresses, a single "a@x.com, b@x.com" comma-separated string, or a
        # bare address — and strips any "Display Name <addr>" wrapper so the
        # comparison is against the raw mailbox. Blank tokens are dropped.
        #
        # @return [Array<String>] individual recipient addresses
        def recipient_mailboxes(value)
          Array(value)
            .flat_map { |entry| entry.to_s.split(',') }
            .map { |token| token[/<([^>]+)>/, 1] || token }
            .map(&:strip)
            .reject(&:empty?)
        end

        # Normalize email hash to ensure required fields
        def normalize_email(email)
          {
            to: normalize_recipients(email[:to]),
            from: email[:from].to_s,
            reply_to: email[:reply_to]&.to_s,
            subject: email[:subject].to_s,
            text_body: email[:text_body].to_s,
            html_body: email[:html_body]&.to_s,
          }
        end

        # Check if we have HTML content
        def html_content?(email)
          !email[:html_body].to_s.empty?
        end
      end
    end
  end
end

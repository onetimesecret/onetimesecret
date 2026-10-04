# lib/onetime/jobs/workers/email_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../mail'
require_relative '../../models/custom_domain/mailer_config'
require_relative '../../models/delivery_event'

module Onetime
  module Jobs
    module Workers
      # Email delivery worker
      #
      # Consumes messages from email.message.send queue and delivers emails
      # via Onetime::Mail.deliver. Implements retry logic and dead letter
      # queue handling for failed deliveries.
      #
      # Message formats:
      #   Templated email:
      #   {
      #     "template": "secret_link",
      #     "data": { "secret_key": "abc123", "share_domain": null, "recipient": "user@example.com", "sender_email": "sender@example.com" }
      #   }
      #
      #   Raw email (for Rodauth integration):
      #   {
      #     "raw": true,
      #     "email": { "to": "user@example.com", "from": "...", "subject": "...", "body": "..." }
      #   }
      #
      #   Either form may carry top-level "correlation_id", "event_type" and
      #   "customer_extid" (set by DispatchNotification). They are read for
      #   the delivery event only and never reach the template.
      #
      # Delivery events: one Onetime::DeliveryEvent per settled message,
      # written after the retries finish.
      #
      #   | Settled | Outcome   | Reason              | When                              |
      #   |---------|-----------|---------------------|-----------------------------------|
      #   | ack     | `sent`    |                     | a mail provider accepted it       |
      #   | ack     | `skipped` | `log_only`          | the logger backend printed it     |
      #   | ack     | `skipped` | `not_dispatched`    | suppressed recipient, or disabled |
      #   | reject  | `failed`  | `invalid_message`   | not JSON, unknown schema, wrong   |
      #   |         |           |                     | payload shape, no message id, or  |
      #   |         |           |                     | the mailer refused the input      |
      #   | reject  | `failed`  | `permanent`         | non-transient DeliveryError       |
      #   | reject  | `failed`  | `retries_exhausted` | still failing after the retries   |
      #   | reject  | `failed`  | `error`             | any other error, including one    |
      #   |         |           |                     | raised before delivery started    |
      #
      # Every message the worker rejects writes exactly one `failed` event,
      # whether or not delivery was attempted. A message rejected after its
      # idempotency claim was taken releases the claim, so a DLQ replay of
      # the same message id is delivered. Three paths write nothing: a
      # duplicate dropped by the idempotency claim (ack), a ping message
      # (ack), and a non-StandardError such as a shutdown signal, which is
      # re-raised without settling the message. Recording is best-effort and
      # does not change ack/reject behavior.
      #
      # Configuration:
      #   - threads: Number of concurrent workers (4 recommended)
      #   - prefetch: Number of messages to prefetch (10 recommended)
      #   - ack: Manual acknowledgment for reliability
      #
      class EmailWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'email.message.send'

        # A message that parsed as JSON but cannot be delivered as written:
        # wrong payload shape, or no message id to claim it by. Rejected to
        # the DLQ without a delivery attempt. The text is fixed wording and
        # never echoes payload content.
        class InvalidMessage < ArgumentError; end

        # What one work_with_params call knows about its message: the frozen
        # envelope, and two flags that change as the call proceeds. `recorded`
        # keeps the call to one delivery event (ack! can raise into a rescue
        # path); `claim_held` says whether the call holds an idempotency claim
        # that a failure should release. Built per call and passed to the
        # helpers, never stored on the worker.
        Invocation = Struct.new(:envelope, :recorded, :claim_held) do
          # @return [String, nil] the AMQP message id of the message
          def message_id
            envelope.message_id
          end
        end

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('EMAIL_WORKER_THREADS', 4).to_i,
          prefetch: ENV.fetch('EMAIL_WORKER_PREFETCH', 10).to_i

        # Process email delivery message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          # Everything the rescue clauses read is set before any call that
          # can raise, so a failure on the first line still rejects the
          # message and records its event.
          data       = nil
          attempts   = 0
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          envelope   = Envelope.new(delivery_info, metadata)
          invocation = Invocation.new(envelope, false, false)

          # Instrument entry point - log before the message is touched
          log_info 'Message received',
            message_id: envelope.message_id || 'unknown',
            delivery_tag: envelope.delivery_tag || 'unknown'

          with_trace_context(envelope) do
            data = decode_message(msg, envelope)
            if data.nil? # not a JSON object, or an unknown schema version (already logged)
              record_delivery_event(
                nil,
                invocation: invocation,
                outcome: 'failed',
                reason: 'invalid_message',
                attempts: attempts,
                started_at: started_at,
              )
              flush_logs
              return reject! # Send to DLQ
            end

            validate_shape!(data)

            # Handle ping test messages (from: bin/ots queue ping)
            if ping_test?(data)
              log_info 'Received ping test', template: data[:template], ping_id: data.dig(:data, :ping_id)
              return ack!
            end

            validate_deliverable!(data, invocation.message_id)

            # Atomic idempotency claim: only one worker can claim a message
            unless claim_for_processing(invocation.message_id)
              log_info "Skipping duplicate message: #{invocation.message_id}"
              return ack!
            end
            invocation.claim_held = true

            log_debug "Processing email: #{data[:template]} (metadata: #{envelope.summary})"

            # Transient DeliveryErrors and plain StandardErrors are retried.
            # Non-transient DeliveryErrors (auth failure, permanent rejection)
            # and ArgumentErrors (the mailer refused the input, e.g. an
            # unknown template) are not: a retry cannot change the result.
            retriable = ->(ex) { ex.is_a?(Onetime::Mail::DeliveryError) ? ex.transient? : !ex.is_a?(ArgumentError) }

            result                = with_retry(max_retries: 3, base_delay: 2.0, retriable: retriable) do
              attempts += 1
              deliver_email(data)
            end
            # Delivery returned: the claim now stays, whatever happens next,
            # so a replay cannot send the email a second time. A delivery
            # call that raised after the provider accepted the message does
            # not get this protection (see release_claim).
            invocation.claim_held = false

            outcome, reason = delivery_outcome(result)
            if outcome == 'sent'
              log_info "Email delivered: #{data[:template]}"
            else
              log_info "Email not transmitted (#{reason}): #{data[:template]}"
            end
            update_delivery_status(data, outcome)
            record_delivery_event(
              data,
              invocation: invocation,
              outcome: outcome,
              reason: reason,
              result: result,
              attempts: attempts,
              started_at: started_at,
            )
            ack!
          end
        rescue InvalidMessage => ex
          log_error "Invalid message format: #{ex.message}", message_id: invocation.message_id
          release_claim(invocation)
          update_delivery_status(data, 'failed')
          record_delivery_event(
            data,
            invocation: invocation,
            outcome: 'failed',
            reason: 'invalid_message',
            error: ex,
            attempts: attempts,
            started_at: started_at,
          )
          flush_logs
          reject! # Send to DLQ
        rescue Onetime::Mail::DeliveryError => ex
          if ex.transient?
            log_error 'Transient delivery error (retries exhausted)', ex
          else
            log_error 'Non-transient delivery error, skipping to DLQ', ex
          end
          release_claim(invocation)
          update_delivery_status(data, 'failed')
          record_delivery_event(
            data,
            invocation: invocation,
            outcome: 'failed',
            reason: ex.transient? ? 'retries_exhausted' : 'permanent',
            error: ex,
            attempts: attempts,
            started_at: started_at,
          )
          flush_logs
          reject! # Send to DLQ
        rescue StandardError => ex
          log_error 'Unexpected error delivering email', ex
          release_claim(invocation)
          update_delivery_status(data, 'failed')
          record_delivery_event(
            data,
            invocation: invocation,
            outcome: 'failed',
            reason: unexpected_failure_reason(ex, attempts),
            error: ex,
            attempts: attempts,
            started_at: started_at,
          )
          flush_logs
          reject! # Send to DLQ
        rescue Exception => ex # rubocop:disable Lint/RescueException
          # Catch non-StandardError exceptions (SignalException, SystemExit, etc.)
          # that would otherwise escape without logging
          log_error 'Fatal exception in email worker (non-StandardError)', ex
          flush_logs
          raise # Re-raise to let Sneakers handle process-level exceptions
        end

        # Templates that support delivery status tracking on the customer model
        TRACKABLE_TEMPLATES = [:email_change_confirmation].freeze

        private

        # Check if this is a ping test message. The payload is a Hash
        # (decode_message) whose template and data passed validate_shape!.
        def ping_test?(data)
          data[:template].to_s == 'ping_test' || (data[:data].is_a?(Hash) && data[:data][:test] == true)
        end

        # Check the types every later step relies on, before anything reads
        # the payload. Runs ahead of the ping check, so it covers pings too.
        # The payload itself is already a Hash: decode_message refuses any
        # other JSON value.
        # @raise [InvalidMessage]
        def validate_shape!(data)
          unless data[:template].nil? || data[:template].is_a?(String)
            raise InvalidMessage, 'template is not a string'
          end

          return if data[:data].nil? || data[:data].is_a?(Hash)

          raise InvalidMessage, 'data is not a JSON object'
        end

        # Check that a non-ping message has what delivery needs: an id to
        # claim it by, and either a template name or a raw email with a
        # recipient. A message with no id cannot be claimed, so it is rejected
        # here instead of being acked as if it were a duplicate.
        # @raise [InvalidMessage]
        def validate_deliverable!(data, msg_id)
          raise InvalidMessage, 'missing message id' if msg_id.to_s.empty?

          if data[:raw]
            email = data[:email]
            raise InvalidMessage, 'raw email is not a JSON object' unless email.is_a?(Hash)
            raise InvalidMessage, 'raw email has no recipient' unless deliverable_recipient?(email[:to])
          elsif data[:template].to_s.strip.empty?
            raise InvalidMessage, 'missing template'
          end
        end

        # Whether the mailer can send to this raw-email recipient. It sends to
        # one mailbox: a String, or the first entry of a list such as
        # Rodauth's Mail::Message#to (Mailer#extract_email_address). Any other
        # value would reach the backend as its to_s, so false would be sent
        # to "false" and 42 to "42".
        def deliverable_recipient?(to)
          to = to.first if to.is_a?(Array)
          to.is_a?(String) && !to.strip.empty?
        end

        # Deliver email via Onetime::Mail
        # Handles both templated and raw email formats
        def deliver_email(data)
          domain_id     = data[:domain_id] || data['domain_id']
          sender_config = Onetime::CustomDomain::MailerConfig.load_for_domain(domain_id) if domain_id

          if data[:raw]
            deliver_raw_email(data, sender_config: sender_config)
          else
            deliver_templated_email(data, sender_config: sender_config)
          end
        rescue Onetime::Mail::DeliveryError => ex
          # Log and re-raise; with_retry's retriable predicate handles
          # whether to retry (transient) or skip to DLQ (non-transient)
          log_error "Mail delivery error (transient=#{ex.transient?}): #{ex.message}"
          raise
        rescue ArgumentError => ex
          # The mailer refused the input (e.g. unknown template). Not
          # retried; re-raise to exit work_with_params and trigger reject!
          log_error "Invalid message format: #{ex.message}"
          raise
        end

        # Deliver templated email. The payload passed validate_deliverable!,
        # so the template name is a non-blank String.
        def deliver_templated_email(data, sender_config: nil)
          template   = data[:template].to_sym
          email_data = data[:data] || {}

          # Extract locale from payload, fall back to configured default locale.
          # A blank locale ("") is truthy in Ruby and would slip past a bare `||`,
          # so normalize (strip) first and treat blank/whitespace the same as missing.
          # Stripping here canonicalizes the value for every enqueue site on the queued
          # delivery path, avoiding an invalid I18n locale like :" en ". (The in-process
          # Publisher fallback path takes a different route and always renders 'en'.)
          locale = (email_data.delete(:locale) || email_data.delete('locale')).to_s.strip
          locale = OT.default_locale if locale.empty?

          Onetime::Mail.deliver(template, email_data, locale: locale, sender_config: sender_config)
        end

        # Deliver raw email (non-templated). The payload passed
        # validate_deliverable!, so the email is a Hash with a recipient.
        def deliver_raw_email(data, sender_config: nil)
          Onetime::Mail.deliver_raw(data[:email], sender_config: sender_config)
        end

        # Map what the mail layer returned to an event outcome and reason
        # (Delivery::Base#deliver contract). Only a provider response is
        # `sent`; the backend, not this worker, says when it did not transmit.
        #
        # @param result [Object, Onetime::Mail::Delivery::NotTransmitted, nil]
        # @return [Array(String, String|nil)] outcome, reason
        def delivery_outcome(result)
          case result
          when nil
            %w[skipped not_dispatched]
          when Onetime::Mail::Delivery::NotTransmitted
            ['skipped', result.reason]
          else
            ['sent', nil]
          end
        end

        # Write the one terminal event for this invocation. Called on every
        # path that settles a message except duplicates and pings; the guard
        # on the invocation keeps it to one event when a later step (ack!)
        # raises into a rescue path. Best-effort.
        #
        # Payload fields are copied only when they are Strings, so a payload
        # rejected for its shape cannot put a mistyped value in the event. A
        # message rejected before it parsed has no payload: its event carries
        # the envelope id only.
        #
        # @param data [Hash, Object, nil] Parsed message payload
        # @param invocation [Invocation] this call and its one-event guard
        # @param outcome [String] 'sent', 'skipped' or 'failed'
        # @param reason [String, nil] reason code
        # @param result [Object, nil] Mail backend response, when delivered
        # @param error [Exception, nil] the terminal error, when failed
        def record_delivery_event(data, invocation:, outcome:, attempts:, started_at:, reason: nil, result: nil, error: nil)
          return if invocation.recorded

          invocation.recorded = true
          data                = {} unless data.is_a?(Hash)
          fields              = data.slice(:correlation_id, :event_type, :template, :customer_extid)
            .select { |_key, value| value.is_a?(String) }

          Onetime::DeliveryEvent.record(
            channel: 'email',
            stage: 'delivery',
            outcome: outcome,
            reason: reason,
            error: error,
            correlation_id: fields[:correlation_id] || invocation.message_id,
            message_id: invocation.message_id,
            event_type: fields[:event_type],
            template: data[:raw] ? 'raw' : fields[:template],
            customer_id: fields[:customer_extid],
            provider: mail_provider_name,
            provider_message_id: provider_message_id_of(result),
            attempt_count: attempts,
            duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round,
          )
        rescue StandardError => ex
          log_error "Delivery event not recorded: #{ex.class}"
        end

        # Release the idempotency claim when this invocation took it and
        # delivery did not finish, so a DLQ replay of the same message id is
        # delivered instead of being acked as a duplicate for the rest of the
        # claim TTL. A claim this invocation did not take is left alone: it
        # belongs to another delivery of the same id. Best-effort: the release
        # never raises (BaseWorker#release_processing_claim_safely).
        #
        # Delivery is at-least-once. "Did not finish" means the delivery call
        # raised, which is not proof the provider did not accept the message:
        # a read timeout after the provider accepted it, or an error raised
        # inside Delivery::Base#deliver after the send, lands here too. The
        # claim is released, the message goes to the DLQ, and a replay sends
        # the email a second time. Keeping the claim instead would drop the
        # replay of every message that really was not sent.
        def release_claim(invocation)
          return unless invocation.claim_held

          invocation.claim_held = false
          release_processing_claim_safely(invocation.message_id)
        end

        # Reason code for an error that is not a DeliveryError. An
        # ArgumentError is the mailer refusing the input. Otherwise the error
        # either outlasted the retries, or was raised once: before delivery
        # started (attempts 0) or after it finished.
        def unexpected_failure_reason(ex, attempts)
          return 'invalid_message' if ex.is_a?(ArgumentError)

          attempts > 1 ? 'retries_exhausted' : 'error'
        end

        # @return [String, nil] the transport the mail backend is built for
        def mail_provider_name
          Onetime::Mail::Mailer.backend_provider
        rescue StandardError
          nil
        end

        # Provider message id when the backend response carries one (SES
        # `message_id`, SMTP Mail::Message#message_id, SMTP2GO `email_id`).
        # Optional: not every transport returns one.
        # @return [String, nil]
        def provider_message_id_of(result)
          value = if result.respond_to?(:message_id)
                    result.message_id
                  elsif result.is_a?(Hash)
                    result['message_id'] || result[:message_id] || result['email_id']
                  end
          value.nil? ? nil : value.to_s
        rescue StandardError
          nil
        end

        # Update the customer's pending_email_delivery_status field.
        # Only applies to email change confirmation emails that include
        # a customer_objid in their data payload.
        #
        # The status is the delivery outcome, so a message the backend only
        # logged or did not dispatch reads 'skipped', not 'sent'. Nothing
        # depends on the value to complete the email change; with the logger
        # backend the confirmation link is in the log either way.
        #
        # @param data [Hash, Object, nil] Parsed message payload
        # @param status [String] 'sent', 'skipped' or 'failed'
        def update_delivery_status(data, status)
          return unless data.is_a?(Hash) && data[:template].is_a?(String) && data[:data].is_a?(Hash)
          return unless TRACKABLE_TEMPLATES.include?(data[:template].to_sym)

          customer_objid = data[:data][:customer_objid]
          return unless customer_objid

          customer = Onetime::Customer.find_by_identifier(customer_objid)
          unless customer
            log_debug "Customer not found for delivery status update: #{customer_objid}"
            return
          end

          customer.pending_email_delivery_status = status
          log_debug "Updated delivery status to '#{status}' for customer #{customer_objid}"
        rescue StandardError => ex
          # Status tracking is best-effort; don't let it break delivery flow
          log_error "Failed to update delivery status: #{ex.message}"
        end
      end
    end
  end
end

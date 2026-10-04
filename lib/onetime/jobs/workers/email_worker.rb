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
      # Delivery events: one Onetime::DeliveryEvent per processed message,
      # written after the retries finish — `sent` when the backend accepted
      # the message, `skipped` when it returned nil (suppressed recipient or
      # delivery disabled), `failed` on a permanent error, exhausted retries,
      # or an invalid message. Duplicates dropped by the idempotency claim and
      # ping messages write nothing. Recording is best-effort and does not
      # change ack/reject behavior.
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

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('EMAIL_WORKER_THREADS', 4).to_i,
          prefetch: ENV.fetch('EMAIL_WORKER_PREFETCH', 10).to_i

        # Process email delivery message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          # Instrument entry point - log before ANY other code runs
          msg_id       = metadata&.message_id || 'unknown'
          delivery_tag = delivery_info&.delivery_tag || 'unknown'
          log_info 'Message received', message_id: msg_id, delivery_tag: delivery_tag

          store_envelope(delivery_info, metadata)

          data          = nil
          attempts      = 0
          started_at    = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          # A worker instance processes messages concurrently. Keep the guard
          # and event identity local, including when ack! enters a rescue path.
          event_context = { recorded: false, message_id: metadata&.message_id }
          with_trace_context do
            data = parse_message(msg)
            unless data # parse_message already rejected the message
              record_delivery_event(
                nil,
                event_context: event_context,
                attempts: attempts,
                started_at: started_at,
                reason: 'invalid_message',
              )
              return
            end

            # Handle ping test messages (from: bin/ots queue ping)
            if ping_test?(data)
              log_info 'Received ping test', template: data[:template], ping_id: data.dig(:data, :ping_id)
              return ack!
            end

            # Atomic idempotency claim: only one worker can claim a message
            unless claim_for_processing(message_id)
              log_info "Skipping duplicate message: #{message_id}"
              return ack!
            end

            log_debug "Processing email: #{data[:template]} (metadata: #{message_metadata})"

            # Only skip retries for non-transient DeliveryErrors (auth failure, permanent rejection).
            # Plain StandardErrors and transient DeliveryErrors are retriable.
            retriable = ->(ex) { !ex.is_a?(Onetime::Mail::DeliveryError) || ex.transient? }

            result = with_retry(max_retries: 3, base_delay: 2.0, retriable: retriable) do
              attempts += 1
              deliver_email(data)
            end

            log_info "Email delivered: #{data[:template]}"
            update_delivery_status(data, 'sent')
            record_delivery_event(
              data,
              event_context: event_context,
              result: result,
              attempts: attempts,
              started_at: started_at,
            )
            ack!
          end
        rescue Onetime::Mail::DeliveryError => ex
          if ex.transient?
            log_error 'Transient delivery error (retries exhausted)', ex
          else
            log_error 'Non-transient delivery error, skipping to DLQ', ex
          end
          update_delivery_status(data, 'failed')
          record_delivery_event(
            data,
            event_context: event_context,
            error: ex,
            attempts: attempts,
            started_at: started_at,
            reason: ex.transient? ? 'retries_exhausted' : 'permanent',
          )
          flush_logs
          reject! # Send to DLQ
        rescue StandardError => ex
          log_error 'Unexpected error delivering email', ex
          update_delivery_status(data, 'failed')
          record_delivery_event(
            data,
            event_context: event_context,
            error: ex,
            attempts: attempts,
            started_at: started_at,
            reason: unexpected_failure_reason(ex, attempts),
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

        # Check if this is a ping test message
        def ping_test?(data)
          data[:template]&.to_sym == :ping_test || data.dig(:data, :test) == true
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
          # Bad message format - don't retry, send to DLQ
          log_error "Invalid message format: #{ex.message}"
          raise # Re-raise to exit work_with_params and trigger reject!
        end

        # Deliver templated email
        def deliver_templated_email(data, sender_config: nil)
          template   = data[:template]&.to_sym
          email_data = data[:data] || {}

          unless template
            raise ArgumentError, 'Missing template in message payload'
          end

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

        # Deliver raw email (non-templated)
        def deliver_raw_email(data, sender_config: nil)
          email = data[:email]

          unless email && email[:to]
            raise ArgumentError, 'Missing email data in raw message payload'
          end

          Onetime::Mail.deliver_raw(email, sender_config: sender_config)
        end

        # Write one terminal event per invocation, including parse rejections
        # with zero delivery attempts and no payload fields. Duplicates and
        # ping messages never call this helper. Best-effort.
        #
        # @param data [Hash, nil] Parsed message payload
        # @param result [Object, nil] Mail backend response; nil means the
        #   backend skipped the send (Delivery::Base#deliver contract)
        # @param error [Exception, nil] the terminal error, when failed
        def record_delivery_event(data, event_context:, attempts:, started_at:, result: nil, error: nil, reason: nil)
          parse_rejected = data.nil? && attempts.zero? && reason == 'invalid_message'
          return if (data.nil? || attempts.zero?) && !parse_rejected
          return if event_context[:recorded]

          event_context[:recorded] = true
          data                   ||= {}

          outcome, reason = if error || parse_rejected
                              ['failed', reason]
                            elsif result.nil?
                              %w[skipped not_dispatched]
                            else
                              ['sent', nil]
                            end

          Onetime::DeliveryEvent.record(
            channel: 'email',
            stage: 'delivery',
            outcome: outcome,
            reason: reason,
            error: error,
            correlation_id: data[:correlation_id] || event_context[:message_id],
            message_id: event_context[:message_id],
            event_type: data[:event_type],
            template: data[:raw] ? 'raw' : data[:template],
            customer_id: data[:customer_extid],
            provider: mail_provider_name,
            provider_message_id: provider_message_id_of(result),
            attempt_count: attempts,
            duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round,
          )
        rescue StandardError => ex
          log_error "Delivery event not recorded: #{ex.class}"
        end

        def unexpected_failure_reason(ex, attempts)
          return 'invalid_message' if ex.is_a?(ArgumentError)

          attempts > 1 ? 'retries_exhausted' : 'error'
        end

        # @return [String, nil] configured transport name
        def mail_provider_name
          Onetime::Mail::Mailer.determine_provider
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
        # @param data [Hash] Parsed message payload
        # @param status [String] 'sent' or 'failed'
        def update_delivery_status(data, status)
          template = data[:template]&.to_sym
          return unless TRACKABLE_TEMPLATES.include?(template)

          customer_objid = data.dig(:data, :customer_objid)
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

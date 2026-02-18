# lib/onetime/jobs/workers/email_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../mail'

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
          store_envelope(delivery_info, metadata)

          data = parse_message(msg)
          return unless data # parse_message handles reject on error

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

          with_retry(max_retries: 3, base_delay: 2.0, retriable: retriable) do
            deliver_email(data)
          end

          log_info "Email delivered: #{data[:template]}"
          update_delivery_status(data, 'sent')
          ack!
        rescue Onetime::Mail::DeliveryError => ex
          if ex.transient?
            log_error 'Transient delivery error (retries exhausted)', ex
          else
            log_error 'Non-transient delivery error, skipping to DLQ', ex
          end
          update_delivery_status(data, 'failed')
          reject! # Send to DLQ
        rescue StandardError => ex
          log_error 'Unexpected error delivering email', ex
          update_delivery_status(data, 'failed')
          reject! # Send to DLQ
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
          if data[:raw]
            deliver_raw_email(data)
          else
            deliver_templated_email(data)
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
        def deliver_templated_email(data)
          template   = data[:template]&.to_sym
          email_data = data[:data] || {}

          unless template
            raise ArgumentError, 'Missing template in message payload'
          end

          # Extract locale from payload, fall back to configured default locale
          locale = email_data.delete(:locale) || email_data.delete('locale') || OT.default_locale

          Onetime::Mail.deliver(template, email_data, locale: locale)
        end

        # Deliver raw email (non-templated)
        def deliver_raw_email(data)
          email = data[:email]

          unless email && email[:to]
            raise ArgumentError, 'Missing email data in raw message payload'
          end

          Onetime::Mail.deliver_raw(email)
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

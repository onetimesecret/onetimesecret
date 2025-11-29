# lib/onetime/jobs/workers/email_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require_relative 'base_worker'

module Onetime
  module Jobs
    module Workers
      # Email delivery worker
      #
      # Consumes messages from email.immediate queue and delivers emails
      # via Onetime::Mail.deliver. Implements retry logic and dead letter
      # queue handling for failed deliveries.
      #
      # Message formats:
      #   Templated email:
      #   {
      #     "template": "secret_link",
      #     "data": { "secret_id": "abc123", "recipient": "user@example.com" }
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

        from_queue 'email.immediate',
                   ack: true,
                   threads: ENV.fetch('EMAIL_WORKER_THREADS', 4).to_i,
                   prefetch: ENV.fetch('EMAIL_WORKER_PREFETCH', 10).to_i

        # Process email delivery message
        # @param msg [String] JSON-encoded message
        def work(msg)
          data = parse_message(msg)
          return unless data # parse_message handles reject on error

          log_debug "Processing email: #{data[:template]} (metadata: #{message_metadata})"

          with_retry(max_retries: 3, base_delay: 2.0) do
            deliver_email(data)
          end

          log_info "Email delivered: #{data[:template]}"
          ack!
        rescue StandardError => e
          log_error "Unexpected error delivering email", e
          reject! # Send to DLQ
        end

        private

        # Deliver email via Onetime::Mail
        # Handles both templated and raw email formats
        def deliver_email(data)
          require_relative '../../mail'

          if data[:raw]
            deliver_raw_email(data)
          else
            deliver_templated_email(data)
          end
        rescue Onetime::Mail::DeliveryError => e
          # Mail-specific errors - these might be transient
          log_error "Mail delivery error: #{e.message}"
          raise # Trigger retry logic
        rescue ArgumentError => e
          # Bad message format - don't retry
          log_error "Invalid message format: #{e.message}"
          reject!
        end

        # Deliver templated email
        def deliver_templated_email(data)
          template = data[:template]&.to_sym
          email_data = data[:data] || {}

          unless template
            raise ArgumentError, 'Missing template in message payload'
          end

          Onetime::Mail.deliver(template, email_data)
        end

        # Deliver raw email (non-templated)
        def deliver_raw_email(data)
          email = data[:email]

          unless email && email[:to]
            raise ArgumentError, 'Missing email data in raw message payload'
          end

          Onetime::Mail.deliver_raw(email)
        end
      end
    end
  end
end

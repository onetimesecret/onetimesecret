# lib/onetime/jobs/workers/domain_validation_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../operations/validate_sender_domain'
require_relative '../../models/custom_domain/mailer_config'

#
# Processes DNS validation requests from the domain.validation.check queue.
#
# This worker enables asynchronous DNS validation for custom domain sender
# configurations. The web process sets verification_status to 'pending',
# enqueues a message, and returns immediately. This worker then performs
# the (potentially slow) DNS lookups at its own pace.
#
# Message payload schema:
# {
#   domain_id: 'abc123',            # CustomDomain identifier (MailerConfig key)
#   requested_at: '2024-01-01T00:00:00Z',  # When validation was requested
# }
#
# ## Why background?
#
# ValidateSenderDomain performs sequential DNS lookups (up to 5 for SES).
# Under degraded DNS conditions, each lookup can block for up to 5 seconds
# (Resolv::DNS default timeout), compounding to 25s worst case. Moving
# this to a worker makes the user-facing response instant.
#
# The operation's existing design (immutable Result, persist: true,
# pending/verified/failed status) already supports async execution --
# the web request just needs to enqueue and return 'pending'.
#

module Onetime
  module Jobs
    module Workers
      class DomainValidationWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'domain.validation.check'

        # Conservative defaults for initial rollout. DNS-bound workers spend
        # most time in I/O wait, so 8-16 threads would be safe here. Tune
        # via env vars once production telemetry shows DNS response distributions.
        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('DOMAIN_VALIDATION_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('DOMAIN_VALIDATION_WORKER_PREFETCH', 5).to_i

        # Process domain validation message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = parse_message(msg)
          return unless data # parse_message handles reject on error

          # Handle ping test messages (from: bin/ots queue ping)
          if data[:domain_id] == 'ping.test'
            log_info 'Received ping test', domain_id: data[:domain_id]
            return ack!
          end

          # Atomic idempotency claim: only one worker can claim a message
          unless claim_for_processing(message_id)
            log_info "Skipping duplicate message: #{message_id}"
            return ack!
          end

          domain_id    = data[:domain_id]
          bypass_cache = data[:bypass_cache] || false  # Backward compat for in-flight messages
          log_debug "Validating sender domain DNS: #{domain_id} (bypass_cache: #{bypass_cache}, metadata: #{message_metadata})"

          # Load the mailer config for this domain
          mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(domain_id)
          unless mailer_config
            log_error "MailerConfig not found for domain_id: #{domain_id}", message_id: message_id, metadata: message_metadata
            return ack! # Don't retry -- config won't appear on its own
          end

          # Delegate to operation with retry logic (DNS can be transiently flaky)
          # Don't retry rate limits - they won't clear for ~60 minutes
          result = nil
          with_retry(
            max_retries: 2,
            base_delay: 2.0,
            retriable: ->(ex) { !ex.is_a?(Onetime::LimitExceeded) },
          ) do
            result = Onetime::Operations::ValidateSenderDomain.new(
              mailer_config: mailer_config,
              persist: true,
              bypass_cache: bypass_cache,
            ).call
            # Re-raise so with_retry can retry transient DNS failures.
            # ValidateSenderDomain#call rescues internally and returns a
            # Result — without this, with_retry never sees an exception.
            raise result.error if result.error
          end

          log_info "Sender domain validation complete: #{domain_id}",
            status: result.verification_status,
            all_verified: result.all_verified,
            persisted: result.persisted,
            bypass_cache: bypass_cache,
            error: result.error

          ack!
        rescue Onetime::LimitExceeded => ex
          # Rate limited - ack the message (don't retry or DLQ)
          # User can manually re-trigger after the rate limit window
          log_info 'Sender domain validation rate limited',
            domain_id: domain_id,
            retry_after: ex.retry_after,
            attempts: ex.attempts,
            max_attempts: ex.max_attempts
          ack!
        rescue StandardError => ex
          log_error 'Unexpected error validating sender domain', ex
          reject! # Send to DLQ
        end
      end
    end
  end
end

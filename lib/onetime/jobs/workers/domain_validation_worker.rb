# lib/onetime/jobs/workers/domain_validation_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../operations/validate_sender_domain'
require_relative '../../models/custom_domain/mailer_config'
require 'onetime/mail/mailer'

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

        # Validate that provider credentials are configured at boot time.
        # This prevents the worker from starting if it can't perform
        # provider-level verification checks.
        def self.check_essentials!
          provider = begin
                       Onetime::Mail::Mailer.determine_provider
          rescue StandardError
                       nil
          end
          return if provider.to_s.empty? || provider.to_s == 'smtp'

          creds = begin
                    Onetime::Mail::Mailer.provider_credentials(provider)
          rescue StandardError
                    nil
          end
          return if creds && !creds.empty?

          raise Onetime::Problem,
            "#{worker_name}: Missing #{provider} provider credentials. " \
            'Set the required environment variables or use --skip-checks to continue.'
        end

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

          # Provider-level verification: ask the provider API if the domain is verified.
          # This complements the DNS validation above.
          begin
            provider = mailer_config.effective_provider
            if provider && provider != 'smtp'
              require 'onetime/mail/sender_strategies'
              sender_strategy = Onetime::Mail::SenderStrategies.for_provider(provider)
              creds           = Onetime::Mail::Mailer.provider_credentials(provider)

              if creds && !creds.empty?
                provider_result = sender_strategy.check_provider_verification_status(mailer_config, credentials: creds)
                log_info "Provider verification check: #{domain_id}",
                  provider: provider,
                  verified: provider_result[:verified],
                  status: provider_result[:status]
              else
                log_debug "Skipping provider check: no credentials for #{provider}"
              end
            end

            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_check_completed_at, :updated)
          rescue StandardError => ex
            # Provider check failure should not fail the overall worker
            log_error "Provider verification check failed for #{domain_id}", ex
            # Still mark as completed so polling doesn't hang
            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_check_completed_at, :updated)
          end

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

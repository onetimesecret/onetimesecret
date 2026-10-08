# lib/onetime/jobs/workers/domain_validation_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative 'job_lifecycle'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../operations/validate_sender_domain'
require_relative '../../operations/check_provider_verification'
require_relative '../../models/custom_domain/mailer_config'
require 'onetime/mail/mailer'
require 'onetime/mail/provider_registry'

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
# ## Data Flow
#
# This worker calls ValidateSenderDomain which uses the DomainValidation::
# SenderStrategies (e.g., LettermintValidation) -- NOT Mail::SenderStrategies.
#
# Input (from mailer_config.dns_records.value, normalized by required_dns_records):
#   [
#     { type: 'TXT', host: 'lettermint._domainkey.example.com',
#       value: 'v=DKIM1;k=rsa;p=...', purpose: 'DKIM' },
#     { type: 'CNAME', host: 'lm-bounces.example.com',
#       value: 'bounces.lmta.net', purpose: 'SPF/Return-Path' },
#     { type: 'TXT', host: '_dmarc.example.com',
#       value: 'v=DMARC1;p=none', purpose: 'DMARC' },
#   ]
#
# Output (ValidateSenderDomain::Result):
#   Result.new(
#     domain: 'example.com',
#     provider: 'lettermint',
#     dns_records: [
#       { type: 'TXT', host: '...', expected: '...', actual: ['...'],
#         verified: true, purpose: 'DKIM', error_type: nil },
#     ],
#     all_verified: true,           # All records passed verification
#     verification_status: 'verified',  # Persisted to mailer_config
#     verified_at: Time.now,
#     persisted: true,
#     error: nil,
#     rate_limit: { remaining: 99, ... },
#   )
#
# Persists: mailer_config.verification_status ('verified' | 'failed' | 'pending')
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
        #
        # Checks the provider's REQUIRED keys via ProviderRegistry, not hash
        # emptiness: a builder may bake non-secret defaults into an otherwise
        # credentialed hash, so key-level checks are the robust contract
        # (smtp2go now signals a missing api_key with an empty hash, but the
        # required-key check stays the guard either way).
        def self.check_essentials!
          provider = begin
                       Onetime::Mail::Mailer.determine_provider
          rescue StandardError
                       nil
          end
          # Only provisioning providers have a provider verification API to
          # guard (skips smtp and non-provider transports like logger).
          return unless Onetime::Mail::ProviderRegistry.provisioning_provider?(provider)

          creds   = begin
                    Onetime::Mail::Mailer.provider_credentials(provider)
          rescue StandardError
                    nil
          end
          missing = Onetime::Mail::ProviderRegistry.missing_required_credentials(provider, creds)
          return if missing.empty?

          raise Onetime::Problem,
            "#{worker_name}: Missing #{provider} provider credentials " \
            "(#{missing.join(', ')}). " \
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
        # rubocop:disable Metrics/PerceivedComplexity -- Worker handles validation, provider check, error states
        def work_with_params(msg, delivery_info, metadata)
          envelope = Envelope.new(delivery_info, metadata)

          data          = nil
          mailer_config = nil
          domain_id     = nil
          with_trace_context(envelope) do
            data = decode_message(msg, envelope)
            return reject! unless data # not a JSON object or unknown schema (logged): send to DLQ

            # Handle ping test messages (from: bin/ots queue ping)
            if data[:domain_id] == 'ping.test'
              log_info 'Received ping test', domain_id: data[:domain_id]
              return ack!
            end

            # Atomic idempotency claim: only one worker can claim a message
            unless claim_for_processing(envelope.message_id)
              log_info "Skipping duplicate message: #{envelope.message_id}"
              return ack!
            end

            domain_id    = data[:domain_id]
            bypass_cache = data[:bypass_cache] || false  # Backward compat for in-flight messages
            log_debug "Validating sender domain DNS: #{domain_id} (bypass_cache: #{bypass_cache}, metadata: #{envelope.summary})"

            # Load the mailer config for this domain
            mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(domain_id)
            unless mailer_config
              log_error "MailerConfig not found for domain_id: #{domain_id}", message_id: envelope.message_id, metadata: envelope.summary
              return ack! # Don't retry -- config won't appear on its own
            end

            # Mark job as processing
            mailer_config.provider_check_status = JobLifecycle::PROCESSING
            mailer_config.save_fields(:provider_check_status)

            # Delegate to operation with retry logic (DNS can be transiently flaky)
            # Don't retry rate limits - they won't clear for ~60 minutes
            result = nil
            with_retry(
              max_retries: 2,
              base_delay: 2.0,
              retriable: ->(ex) { !ex.is_a?(Onetime::LimitExceeded) },
            ) do
              # persist: false because this worker controls verification_status
              # through update_verification_status! after BOTH workers complete.
              # The operation would otherwise set verification_status='verified'
              # based on DNS alone, before the provider API check runs.
              result = Onetime::Operations::ValidateSenderDomain.new(
                mailer_config: mailer_config,
                persist: false,
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

            # Provider-level verification: ask the provider API if the domain
            # is verified, complementing the DNS validation above. Shared with
            # the jobs-disabled fallback in Publisher#enqueue_domain_validation
            # so both paths close the provider check the same way (tri-state
            # provider_verified; a raise inside completes without demoting).
            Onetime::Operations::CheckProviderVerification.new(
              mailer_config: mailer_config,
              dns_all_verified: result.all_verified,
              domain_id: domain_id,
              logger: logger,
            ).call

            # Refresh from Redis so we see the DNS worker's latest status, not our
            # in-memory copy which was loaded before that worker ran.
            mailer_config.refresh!

            # Update stored verification_status if both jobs are now complete
            if mailer_config.jobs_completed?
              final_status = mailer_config.update_verification_status!
              log_info "Domain validation final determination: #{domain_id}",
                verification_status: final_status,
                dns_verified: mailer_config.dns_verified,
                provider_verified: mailer_config.provider_verified
            else
              log_info "Domain validation awaiting DNS check: #{domain_id}",
                provider_verified: mailer_config.provider_verified,
                dns_check_status: mailer_config.dns_check_status
            end

            ack!
          end
        rescue Onetime::LimitExceeded => ex
          # Rate limited - ack the message (don't retry or DLQ)
          # User can manually re-trigger after the rate limit window
          # Mark as completed (not failed) but without setting provider_verified
          if mailer_config
            mailer_config.provider_check_status       = JobLifecycle::COMPLETED
            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.last_error                  = "Rate limited: retry after #{ex.retry_after}s"
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_check_status, :provider_check_completed_at, :last_error, :updated)
          end

          log_info 'Sender domain validation rate limited',
            domain_id: domain_id,
            retry_after: ex.retry_after,
            attempts: ex.attempts,
            max_attempts: ex.max_attempts
          ack!
        rescue StandardError => ex
          # Mark job as failed before sending to DLQ
          if mailer_config
            mailer_config.provider_check_status       = JobLifecycle::FAILED
            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.last_error                  = ex.message
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_check_status, :provider_check_completed_at, :last_error, :updated)
          end

          log_error 'Unexpected error validating sender domain', ex
          reject! # Send to DLQ
        end
        # rubocop:enable Metrics/PerceivedComplexity
      end
    end
  end
end

# lib/onetime/jobs/workers/domain_validation_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative 'job_lifecycle'
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
        # rubocop:disable Metrics/PerceivedComplexity -- Worker handles validation, provider check, error states
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

          # Provider-level verification: ask the provider API if the domain is verified.
          # This complements the DNS validation above.
          provider_api_verified = nil
          begin
            provider = mailer_config.effective_provider
            if provider && provider != 'smtp'
              require 'onetime/mail/sender_strategies'
              sender_strategy = Onetime::Mail::SenderStrategies.for_provider(provider)
              creds           = Onetime::Mail::Mailer.provider_credentials(provider)

              if creds && !creds.empty?
                provider_result       = sender_strategy.check_provider_verification_status(mailer_config, credentials: creds)
                provider_api_verified = provider_result[:verified]
                log_info "Provider verification check: #{domain_id}",
                  provider: provider,
                  verified: provider_result[:verified],
                  status: provider_result[:status]
              else
                log_debug "Skipping provider check: no credentials for #{provider}"
              end
            end

            # Set provider_verified from provider API check when available.
            # Fall back to DNS result only when no provider credentials exist
            # (degraded mode - better than leaving nil).
            mailer_config.provider_verified = if provider_api_verified.nil?
                                                result.all_verified
                                              else
                                                provider_api_verified
                                              end

            # Record provider status when verification fails so UI can explain why
            mailer_config.last_error = provider_api_verified == false && provider_result ? "Provider status: #{provider_result[:status]}" : nil

            # Persist the provider's current domain status back into provider_dns_data
            # so the UI can surface it (e.g. 'verified', 'pending_verification').
            if provider_result
              current_provider_data                 = mailer_config.provider_dns_data.value || {}
              mailer_config.provider_dns_data.value = current_provider_data.merge(
                'status' => provider_result[:status],
              )
            end

            mailer_config.provider_check_status       = JobLifecycle::COMPLETED
            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_verified, :provider_check_status, :provider_check_completed_at, :last_error, :updated)
          rescue StandardError => ex
            # Provider check failure should not fail the overall worker
            log_error "Provider verification check failed for #{domain_id}", ex
            # Mark as completed (not failed - the worker itself didn't crash)
            # but don't set provider_verified since we couldn't determine it
            mailer_config.provider_check_status       = JobLifecycle::COMPLETED
            mailer_config.provider_check_completed_at = Familia.now.to_i
            mailer_config.updated                     = Familia.now.to_i
            mailer_config.save_fields(:provider_check_status, :provider_check_completed_at, :updated)
          end

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

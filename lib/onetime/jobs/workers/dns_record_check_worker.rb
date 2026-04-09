# lib/onetime/jobs/workers/dns_record_check_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative 'job_lifecycle'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../mail/sender_strategies'
require_relative '../../models/custom_domain/mailer_config'

#
# Performs DNS record checks for custom domain sender configurations.
#
# This worker is a pure fact-finder: it looks up what DNS records actually
# exist for a domain and persists the results. No pass/fail judgement is
# made here — that's the caller's responsibility.
#
# Message payload schema:
# {
#   domain_id: 'abc123',                      # CustomDomain identifier (MailerConfig key)
#   requested_at: '2024-01-01T00:00:00Z',     # When the check was requested
# }
#
# ## Why background?
#
# DNS lookups can block for up to 5 seconds per record under degraded
# conditions. Moving this to a worker keeps the user-facing response instant.
#
# ## Data Flow
#
# This worker calls Mail::SenderStrategies::BaseSenderStrategy#check_dns_records
# -- NOT the DomainValidation::SenderStrategies used by DomainValidationWorker.
#
# Input (from mailer_config.dns_records.value, provisioned from Lettermint API):
#   [
#     { 'type' => 'TXT', 'name' => 'lettermint._domainkey.example.com',
#       'value' => 'v=DKIM1;k=rsa;p=...' },
#     { 'type' => 'CNAME', 'name' => 'lm-bounces.example.com',
#       'value' => 'bounces.lmta.net' },
#     { 'type' => 'TXT', 'name' => '_dmarc.example.com',
#       'value' => 'v=DMARC1;p=none' },
#   ]
#
# Output (check_dns_records result, stored to mailer_config.dns_check_results):
#   {
#     records: [
#       {
#         'type' => 'TXT',
#         'name' => 'lettermint._domainkey.example.com',
#         'value' => 'v=DKIM1;k=rsa;p=...',   # expected value
#         'dns_exists' => true,                # record exists in DNS
#         'value_matches' => true,             # expected == actual
#         'error' => nil,                      # DNS lookup error (if any)
#         'expected_digest' => 'sha256...',
#         'actual_digest' => 'sha256...',
#       },
#       # ...
#     ],
#     checked_at: Time.now,
#   }
#
# Persists: mailer_config.dns_check_results.value (Array of record check results)
#           mailer_config.dns_check_completed_at (timestamp)
#
# NOTE: This worker does NOT set verification_status -- that's DomainValidationWorker.
# The 'dns_exists' and 'value_matches' booleans are fact-finding, not verification.
#

module Onetime
  module Jobs
    module Workers
      class DnsRecordCheckWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'domain.dns.check'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('DNS_CHECK_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('DNS_CHECK_WORKER_PREFETCH', 5).to_i

        # Process DNS record check message
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

          domain_id = data[:domain_id]
          log_debug "Checking DNS records: #{domain_id} (metadata: #{message_metadata})"

          # Load the mailer config for this domain
          mailer_config = Onetime::CustomDomain::MailerConfig.find_by_domain_id(domain_id)
          unless mailer_config
            log_error "MailerConfig not found for domain_id: #{domain_id}", message_id: message_id, metadata: message_metadata
            return ack! # Don't retry -- config won't appear on its own
          end

          # Mark job as processing
          mailer_config.dns_check_status = JobLifecycle::PROCESSING
          mailer_config.save_fields(:dns_check_status)

          # Load the sender strategy for DNS lookups (no credentials needed)
          provider = mailer_config.effective_provider
          strategy = Onetime::Mail::SenderStrategies.for_provider(provider)

          # Perform DNS lookups with retry (DNS can be transiently flaky)
          result = nil
          with_retry(max_retries: 1, base_delay: 2.0) do
            result = strategy.check_dns_records(mailer_config, credentials: {})
          end

          # Persist the raw fact-finding results.
          # dns_check_results is a jsonkey (own Redis key), so use value= directly.
          # dns_check_completed_at and updated are scalar fields — save_fields handles those.
          mailer_config.dns_check_results.value = result[:records]

          # Compute dns_verified outcome: true if all records have value_matches=true
          records                    = result[:records] || []
          all_matched                = records.all? { |r| r['value_matches'] == true || r[:value_matches] == true }
          mailer_config.dns_verified = all_matched

          # Mark job as completed
          mailer_config.dns_check_status       = JobLifecycle::COMPLETED
          mailer_config.dns_check_completed_at = Familia.now.to_i
          mailer_config.updated                = Familia.now.to_i
          mailer_config.save_fields(:dns_check_status, :dns_verified, :dns_check_completed_at, :updated)

          # Update stored verification_status if both jobs are now complete
          if mailer_config.jobs_completed?
            final_status = mailer_config.update_verification_status!
            log_info "DNS record check complete (final): #{domain_id}",
              record_count: records.size,
              dns_verified: all_matched,
              verification_status: final_status
          else
            log_info "DNS record check complete: #{domain_id}",
              record_count: records.size,
              dns_verified: all_matched,
              provider_check_status: mailer_config.provider_check_status
          end

          ack!
        rescue StandardError => ex
          # Mark job as failed before sending to DLQ
          if mailer_config
            mailer_config.dns_check_status       = JobLifecycle::FAILED
            mailer_config.dns_check_completed_at = Familia.now.to_i
            mailer_config.last_error             = ex.message
            mailer_config.updated                = Familia.now.to_i
            mailer_config.save_fields(:dns_check_status, :dns_check_completed_at, :last_error, :updated)
          end

          log_error 'Unexpected error checking DNS records', ex
          reject! # Send to DLQ
        end
      end
    end
  end
end

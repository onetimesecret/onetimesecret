# lib/onetime/jobs/scheduled/catalog_retry_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Scheduled job to retry webhook events blocked by circuit breaker
      #
      # When the Stripe circuit breaker opens during webhook processing,
      # events are scheduled for retry rather than failing. This job
      # periodically checks for events due for retry and reprocesses them.
      #
      # The circuit breaker pattern prevents cascade failures during Stripe
      # outages. Once the circuit closes (Stripe recovers), this job ensures
      # pending catalog updates are eventually processed.
      #
      # Configuration:
      #   - Runs every 2 minutes to check for due retries
      #   - Processes up to 50 events per run to avoid overload
      #   - Skips if circuit is still open (waits for recovery)
      #   - Disabled by default; enable via config
      #
      # Enable in config:
      #   jobs:
      #     catalog_retry_enabled: true
      #
      class CatalogRetryJob < ScheduledJob
        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info '[CatalogRetryJob] Scheduling with interval: 2m'

            every(scheduler, '2m', first_in: '30s') do
              process_circuit_retries
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'catalog_retry_enabled') == true
          end

          def process_circuit_retries
            # Skip if no Stripe API key configured
            stripe_key = Onetime.billing_config&.stripe_key
            if stripe_key.to_s.strip.empty?
              scheduler_logger.debug '[CatalogRetryJob] Skipping: No Stripe API key configured'
              return
            end

            # Check circuit breaker state - skip if still open
            if Billing::StripeCircuitBreaker.open?
              scheduler_logger.debug '[CatalogRetryJob] Skipping: Circuit breaker still open'
              return
            end

            # Find events due for retry
            due_events = Billing::StripeWebhookEvent.find_circuit_retry_due(limit: 50)

            if due_events.empty?
              scheduler_logger.debug '[CatalogRetryJob] No events due for circuit retry'
              return
            end

            scheduler_logger.info "[CatalogRetryJob] Processing #{due_events.size} circuit retry events"

            success_count  = 0
            failure_count  = 0
            requeued_count = 0

            due_events.each do |event_record|
              result = process_single_event(event_record)

              case result
              when :success
                success_count += 1
              when :requeued
                requeued_count += 1
              when :failed
                failure_count += 1
              end
            rescue StandardError => ex
              scheduler_logger.error "[CatalogRetryJob] Unexpected error processing #{event_record.stripe_event_id}: #{ex.message}"
              failure_count += 1
            end

            scheduler_logger.info '[CatalogRetryJob] Completed', {
              success: success_count,
              requeued: requeued_count,
              failed: failure_count,
            }
          end

          def process_single_event(event_record)
            stripe_event = event_record.stripe_event
            unless stripe_event
              scheduler_logger.warn "[CatalogRetryJob] Cannot reconstruct event #{event_record.stripe_event_id}"
              return :failed
            end

            scheduler_logger.info "[CatalogRetryJob] Retrying #{event_record.event_type}", {
              event_id: event_record.stripe_event_id,
              retry_count: event_record.circuit_retry_count,
            }

            # Reprocess the event
            operation = Billing::Operations::ProcessWebhookEvent.new(
              event: stripe_event,
              context: {
                source: :circuit_retry,
                webhook_event: event_record,
                retry_count: event_record.circuit_retry_count.to_i,
              },
            )

            result = operation.call

            if result == :queued
              # Handler scheduled another retry (circuit still blocked or rate limited)
              scheduler_logger.info '[CatalogRetryJob] Event requeued for later retry', {
                event_id: event_record.stripe_event_id,
              }
              :requeued
            else
              # Success - clear retry scheduling
              event_record.clear_circuit_retry
              event_record.mark_success!

              scheduler_logger.info '[CatalogRetryJob] Event processed successfully', {
                event_id: event_record.stripe_event_id,
                result: result,
              }
              :success
            end
          rescue Billing::CircuitOpenError => ex
            # Circuit opened again during processing
            if event_record.circuit_retry_exhausted?
              scheduler_logger.error '[CatalogRetryJob] Circuit retry exhausted', {
                event_id: event_record.stripe_event_id,
                retry_count: event_record.circuit_retry_count,
              }
              event_record.mark_failed!(ex)
              :failed
            else
              event_record.schedule_circuit_retry(delay_seconds: ex.retry_after || 60)
              scheduler_logger.warn '[CatalogRetryJob] Circuit open, requeued', {
                event_id: event_record.stripe_event_id,
                retry_after: ex.retry_after,
              }
              :requeued
            end
          rescue Stripe::RateLimitError => ex
            # Rate limited - schedule retry with longer delay
            event_record.schedule_circuit_retry(delay_seconds: 120)
            scheduler_logger.warn '[CatalogRetryJob] Rate limited, requeued', {
              event_id: event_record.stripe_event_id,
              error: ex.message,
            }
            :requeued
          rescue StandardError => ex
            scheduler_logger.error '[CatalogRetryJob] Processing failed', {
              event_id: event_record.stripe_event_id,
              error: ex.message,
            }
            event_record.mark_failed!(ex)
            :failed
          end
        end
      end
    end
  end
end

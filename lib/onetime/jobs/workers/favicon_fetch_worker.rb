# lib/onetime/jobs/workers/favicon_fetch_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../http/safe_fetch'
require_relative '../../operations/fetch_domain_favicon'

#
# Auto-fetches a custom domain's favicon from the live domain (#3780).
#
# This worker is a THIN wrapper: all of the real work — loading the model,
# the overwrite guard, SSRF-guarded discovery/fetch, the icon write, and the
# favicon_fetch_* lifecycle stamps — lives in Onetime::Operations::
# FetchDomainFavicon. The worker only parses the message, enforces the
# idempotency claim, delegates, and translates the operation's raise-vs-return
# contract into RabbitMQ ack/requeue/reject.
#
# Message payload schema:
# {
#   domain_id: 'abc123',                      # CustomDomain identifier (objid)
#   requested_at: '2024-01-01T00:00:00Z',     # When the fetch was requested
#   force: false,                             # optional; Phase 2 manual refresh
# }
#
# ## Why background?
#
# Fetching the favicon involves DNS resolution plus one or more HTTPS hops to
# an arbitrary (customer-controlled) host, each of which can block for seconds.
# Moving it off the request path keeps domain verification instant.
#
# ## Raise-vs-return contract (from FetchDomainFavicon)
#
# The operation RETURNS a Result for every outcome the worker should ack, and
# RAISES only for the two cases the worker must escalate:
#
#   1. Transient (Onetime::Http::SafeFetch::FetchTimeout) — the operation leaves
#      the lifecycle at PROCESSING (no terminal stamp) and re-raises. We retry
#      in-process a couple of times, then requeue! once for a RabbitMQ-level
#      retry. If the redelivery times out too, we reject! to the DLQ.
#   2. Unexpected (any other StandardError) — the operation stamps status=FAILED
#      + favicon_fetch_error and re-raises. We reject! to the DLQ.
#   3. Handled outcomes (icon written, none found, guard skip, domain missing)
#      RETURN a Result and never raise → we ack!. A returned Result with
#      not_found:true means the domain was deleted between enqueue and
#      processing — ack, do NOT DLQ.
#
# Rescue ordering matters: FetchTimeout < SafeFetch::Error < StandardError, so
# the FetchTimeout rescue MUST precede the broad StandardError rescue.
#
# ## Retry layering
#
# There are two retry tiers. `with_retry` retries FetchTimeout in-process (fast,
# same delivery). If those are exhausted the message is requeued once: the
# idempotency claim is released and the broker redelivers it, which runs the
# in-process retries a second time. A redelivered message that times out again
# is rejected to the DLQ, so a host that never answers costs two deliveries and
# not an endless loop. FaviconBackfillJob re-enqueues a domain left at
# PROCESSING once STUCK_PROCESSING_S has passed.
#

module Onetime
  module Jobs
    module Workers
      class FaviconFetchWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'domain.favicon.fetch'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('FAVICON_FETCH_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('FAVICON_FETCH_WORKER_PREFETCH', 5).to_i

        # Process a favicon fetch message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          # Assigned inside the block but declared here: block-locals are
          # invisible to the method-level rescues, which tag their logs with it.
          domain_id = nil

          # Whether this invocation took the idempotency claim.
          claim_held = false

          with_trace_context do
            data = decode_message(msg)
            return reject! unless data # not a JSON object or unknown schema (logged): send to DLQ

            domain_id = data[:domain_id]

            # Handle ping test messages (from: bin/ots queue ping)
            if data[:domain_id] == 'ping.test'
              log_info 'Received ping test', domain_id: data[:domain_id]
              return ack!
            end

            # Feature flag: when disabled, consume and ack so a stray message is
            # dropped cleanly rather than requeued/DLQ'd. The enqueue triggers are
            # flag-gated too, so this is defense-in-depth against a flag flip
            # between enqueue and processing. We ack (not reject) to avoid churn.
            unless favicon_fetch_enabled?
              log_info 'Favicon fetch disabled, dropping message', domain_id: data[:domain_id]
              return ack!
            end

            # Atomic idempotency claim: only one worker can claim a message
            unless claim_for_processing(message_id)
              log_info "Skipping duplicate message: #{message_id}"
              return ack!
            end
            claim_held = true

            # Strict boolean: only an explicit JSON `true` forces. `data[:force] ||
            # false` would treat any truthy payload (e.g. the string "false") as a
            # force, letting a malformed message clobber the skip-existing guard.
            force = data[:force] == true # Phase 2 manual refresh sets this
            log_debug "Fetching favicon: #{domain_id} (force: #{force}, metadata: #{message_metadata})"

            # Delegate to the operation. Retry transient timeouts in-process; the
            # operation re-raises FetchTimeout as-is, so with_retry sees it
            # directly (no explicit re-raise needed here). Non-transient errors
            # are not retriable — they fall straight through to the outer rescue.
            result = nil
            with_retry(
              max_retries: 2,
              base_delay: 2.0,
              retriable: ->(ex) { ex.is_a?(Onetime::Http::SafeFetch::FetchTimeout) },
            ) do
              result = Onetime::Operations::FetchDomainFavicon.new(
                domain_id: domain_id,
                force: force,
              ).call
            end

            # Returned Result → handled outcome. not_found means the domain was
            # deleted between enqueue and processing: ack, do NOT DLQ.
            if result.not_found
              log_info "Favicon fetch skipped, domain no longer exists: #{domain_id}"
            else
              log_info "Favicon fetch complete: #{domain_id}",
                status: result.status,
                favicon_fetched: result.favicon_fetched,
                skipped: result.skipped,
                content_type: result.content_type
            end

            ack!
          end
        rescue Onetime::Http::SafeFetch::FetchTimeout => ex
          # Transient — in-process retries exhausted. The operation left the
          # lifecycle at PROCESSING (no terminal stamp).
          #
          # A redelivery that timed out again goes to the DLQ: the message is
          # requeued once, not for as long as the host stays slow. The claim
          # is kept, as on the unexpected-error reject below. The domain is
          # picked up again by FaviconBackfillJob once it has been PROCESSING
          # for STUCK_PROCESSING_S, under a new message id.
          if delivery_info&.redelivered?
            log_error 'Favicon fetch timed out again after requeue, sending to DLQ', ex, domain_id: domain_id
            return reject!
          end

          log_info 'Favicon fetch timed out, requeueing for retry',
            domain_id: domain_id,
            error: ex.message,
            metadata: message_metadata
          # The broker redelivers under the same message id. Release the claim
          # this invocation took, or the redelivery is acked as a duplicate
          # and the fetch is never retried.
          release_processing_claim_safely(message_id) if claim_held
          requeue!
        rescue StandardError => ex
          # Unexpected — the operation already stamped status=FAILED before
          # re-raising, so we just send the message to the DLQ.
          log_error 'Unexpected error fetching favicon', ex, domain_id: domain_id
          reject! # Send to DLQ
        end

        private

        # Feature flag (blueprint §5). The jobs tree is absent from the in-code
        # DEFAULTS hash, so read with dig and treat anything but true as off.
        def favicon_fetch_enabled?
          OT.conf.dig('jobs', 'favicon_fetch', 'enabled') == true
        end
      end
    end
  end
end

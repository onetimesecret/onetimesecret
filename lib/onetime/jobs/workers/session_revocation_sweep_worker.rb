# lib/onetime/jobs/workers/session_revocation_sweep_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../operations/sessions/revoke_all_for_customer_except_current'

#
# Full async session-revocation sweep after a credential change (#3810).
#
# The password-change/reset hooks revoke tracked sessions in-transaction with
# scan_untracked: false, so untracked (pre-sidecar) blobs would otherwise
# survive until their 24h TTL. This worker re-runs the same operation OUT of
# the transaction with the full keyspace sweep enabled, plus the credential
# watermark so sessions authenticated AFTER the change (the rotated current
# session, a fresh post-reset login) are spared.
#
# This worker is a THIN wrapper: all of the real work — customer resolution,
# the tracked kill, the bounded untracked SCAN, and the watermark guard —
# lives in Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.
# The worker only parses the message, enforces the idempotency claim,
# delegates, and translates the outcome into RabbitMQ ack/reject.
#
# Message payload schema:
# {
#   custid: 'cust_abc123',                    # Customer identifier (extid)
#   except_session_id: 'sid456',              # optional; session to preserve
#   requested_at: '2026-01-01T00:00:00Z',     # When the sweep was requested
# }
#
# ## Why background?
#
# The untracked sweep is a bounded keyspace SCAN plus a GET + AES-256-GCM
# decrypt per candidate — hundreds of ms on a large keyspace. Running it here
# keeps that cost off the request path and out of Rodauth's open SQL
# transaction (see the operation's class docs).
#

module Onetime
  module Jobs
    module Workers
      class SessionRevocationSweepWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'session.revoke.sweep'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('SESSION_SWEEP_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('SESSION_SWEEP_WORKER_PREFETCH', 5).to_i

        # Process a session revocation sweep message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          # Assigned inside the block but declared here: block-locals are
          # invisible to the method-level rescue, which tags its log with it.
          custid = nil

          with_trace_context do
            data = parse_message(msg)
            return unless data # parse_message handles reject on error

            custid = data[:custid]

            # Handle ping test messages (from: bin/ots queue ping)
            if data[:custid] == 'ping.test'
              log_info 'Received ping test', custid: data[:custid]
              return ack!
            end

            # Atomic idempotency claim: only one worker can claim a message
            unless claim_for_processing(message_id)
              log_info "Skipping duplicate message: #{message_id}"
              return ack!
            end

            log_debug "Sweeping sessions: #{custid} (metadata: #{message_metadata})"

            result = Onetime::Operations::Sessions::RevokeAllForCustomerExceptCurrent.new(
              custid: custid,
              except_session_id: data[:except_session_id],
              scan_untracked: true,
              honor_credential_watermark: true,
            ).call

            # A capped scan may have MISSED an untracked blob — a session
            # surviving a password change/reset is a security gap that must be
            # visible, not silent, so log at ERROR. Still ack: replaying the
            # message would hit the same cap.
            if result.scan_capped
              log_error 'Session revocation sweep hit scan cap; an untracked blob may remain',
                custid: custid,
                blobs_deleted: result.blobs_deleted,
                untracked_deleted: result.untracked_deleted
            else
              log_info "Session revocation sweep complete: #{custid}",
                blobs_deleted: result.blobs_deleted,
                untracked_deleted: result.untracked_deleted
            end

            ack!
          end
        rescue StandardError => ex
          # The operation is stateless and idempotent (already-deleted blobs
          # simply aren't found again), so replaying this message from the DLQ
          # is safe.
          log_error 'Unexpected error running session revocation sweep', ex, custid: custid
          reject! # Send to DLQ
        end
      end
    end
  end
end

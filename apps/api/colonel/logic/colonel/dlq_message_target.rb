# apps/api/colonel/logic/colonel/dlq_message_target.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'

module ColonelAPI
  module Logic
    module Colonel
      # The target of the per-message DLQ endpoints (#4343): which queue,
      # which message, and step 2 of the guard-order contract
      # (ColonelAPI::Logic::Base) that every one of them runs after its role
      # check and before its own tier gate. Shared so the three adapters
      # (GetDlqMessage, ReplayDlqMessage, DiscardDlqMessage) cannot drift on
      # the param handling or on what a miss looks like on the wire. The role
      # check (step 1) stays in each class's raise_concerns, where
      # try/integration/api/colonel/bfla_colonel_authz_try.rb reads it.
      #
      # A miss on a configured queue is NOT a 404: the message may be held
      # unacked by a consumer, sit deeper than the scan bound, or the queue
      # may not be declared yet, so the response is 200 with `found: false`
      # and `outcome: 'not_visible'`. 404 is reserved for a queue name outside
      # the allowlist.
      module DlqMessageTarget
        # Publisher ids are SecureRandom.uuid (36 chars); generous headroom.
        MAX_MESSAGE_ID_LENGTH = 128

        attr_reader :queue, :dlq_name, :message_id

        private

        # A queue name keeps dots (sanitize_identifier strips them), as the
        # queue-level DLQ endpoints do; the allowlist is the real gate. A
        # message id keeps [A-Za-z0-9_-], which covers every id we mint.
        def read_dlq_message_target
          @queue      = params['queue'].to_s.downcase.gsub(/[^a-z0-9._-]/, '')
          @dlq_name   = Onetime::Operations::Dlq::Store.resolve(@queue)
          @message_id = sanitize_identifier(params['message_id'].to_s)[0, MAX_MESSAGE_ID_LENGTH].to_s
        end

        # Step 2, after the caller's role check: the target guards. Unknown
        # queue is a 404 before anything touches the broker.
        def verify_dlq_message_target!
          raise_form_error('Queue is required', field: :queue) if @queue.empty?
          unless Onetime::Operations::Dlq::Store.valid?(dlq_name)
            raise_not_found('Unknown dead-letter queue')
          end
          raise_form_error('Message id is required', field: :message_id) if @message_id.empty?
          unless $rmq_conn&.open? # rubocop:disable Style/GlobalVars
            raise_form_error('Message queue is not connected')
          end
        end

        # The record fields all three responses share.
        def dlq_message_scan_record(found:, outcome:, scanned:, truncated:)
          {
            queue: dlq_name,
            message_id: message_id,
            found: found,
            outcome: outcome,
            scanned: scanned.to_i,
            truncated: truncated == true,
          }
        end

        def not_visible_text(scanned, truncated)
          limit = truncated ? ' and stopped at the scan limit' : ''
          "Message #{message_id} is not visible in #{dlq_name} (scanned #{scanned.to_i} message(s)#{limit}). " \
            'A consumer may be holding it, it may be deeper in the queue, or it is gone.'
        end
      end
    end
  end
end

# apps/api/colonel/logic/colonel/get_dlq_messages.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/operations/dlq/store'
require 'onetime/operations/dlq/peek'

module ColonelAPI
  module Logic
    module Colonel
      # Peek the messages in one dead-letter queue (Colonel).
      #
      # Thin adapter over {Onetime::Operations::Dlq::Peek} — the single
      # implementation of the per-queue DLQ list verb (epic #42). Feeds the DLQ
      # console's detail drawer: a non-destructive peek (pop + immediate
      # nack-requeue) of up to `limit` dead-letter payloads for inspection via
      # JsonViewer.
      #
      # Read-only: no AdminAuditEvent (CONTRACT 4).
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role. The
      # `:queue` param is additionally gated against the fixed DLQ allowlist
      # ({Store.valid?}) before the broker is touched — an operator can only ever
      # inspect a configured dead-letter queue.
      class GetDlqMessages < ColonelAPI::Logic::Base
        attr_reader :dlq_name, :result

        # Cap the drawer peek independently of the op's own MAX; the console shows a
        # bounded sample, not a full drain.
        DEFAULT_LIMIT = 20

        def process_params
          @queue    = sanitize_queue_name(params['queue'])
          @dlq_name = Onetime::Operations::Dlq::Store.resolve(@queue)
          @limit    = (params['limit'] || DEFAULT_LIMIT).to_i
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error('Queue is required', field: :queue) if @queue.to_s.empty?
          unless Onetime::Operations::Dlq::Store.valid?(dlq_name)
            raise_not_found('Unknown dead-letter queue')
          end
        end

        def process
          @result = peek_result
          success_data
        end

        private

        # A message-queue name allows lowercase letters, digits, dots, hyphens and
        # underscores (e.g. "billing.event" / "dlq.billing.event"). Unlike
        # sanitize_identifier (which strips dots), this preserves the queue-name
        # shape; the allowlist check in raise_concerns is the real gate.
        def sanitize_queue_name(value)
          value.to_s.downcase.gsub(/[^a-z0-9._-]/, '')
        end

        # Peek the queue, degrading to empty when the broker is down or the queue is
        # configured but not yet declared (Bunny::NotFound).
        def peek_result
          unless $rmq_conn&.open?
            return empty_result
          end

          Onetime::Operations::Dlq::Peek.new(
            connection: $rmq_conn, queue: dlq_name, limit: @limit,
          ).call
        rescue Bunny::NotFound
          empty_result
        end

        def empty_result
          Onetime::Operations::Dlq::Peek::Result.new(
            queue: dlq_name, total_messages: 0, showing: 0, messages: [],
          )
        end

        def success_data
          {
            record: {
              queue: result.queue,
              total_messages: result.total_messages,
              showing: result.showing,
            },
            details: {
              messages: result.messages,
            },
          }
        end
      end
    end
  end
end

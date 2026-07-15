# lib/onetime/operations/dlq/peek.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'

module Onetime
  module Operations
    module Dlq
      # Peek the messages in a single dead-letter queue — the SINGLE implementation
      # of the per-queue DLQ list verb (epic #42 / D3). The colonel endpoint (`GET
      # /api/colonel/queues/dlq/:queue`) and the `bin/ots queue dlq list <queue>`
      # CLI are thin adapters over it.
      #
      # READ-ONLY: every message is popped with a manual ack and immediately
      # nack-requeued ({Store.peek}), so the queue is left exactly as found. No
      # {Onetime::AdminAuditEvent} (CONTRACT 4).
      #
      # Bounded (CONTRACT 6): at most `limit` messages are inspected, clamped to
      # {MAX_LIMIT}, and never more than the queue actually holds — one request can
      # never turn into an unbounded drain.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Peek
        # @!attribute total_messages [r] Integer full queue depth
        # @!attribute messages [r] Array<Hash> the peeked message summaries
        Result = Data.define(:queue, :total_messages, :showing, :messages)

        DEFAULT_LIMIT = 20
        # Hard cap on how many messages a single peek inspects, so an operator can
        # never pop-and-requeue an unbounded queue on the request path.
        MAX_LIMIT = 100

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name (see {Store.resolve}).
        # @param limit [Integer] max messages to peek (clamped to 1..MAX_LIMIT).
        def initialize(connection:, queue:, limit: DEFAULT_LIMIT)
          @connection = connection
          @queue      = queue
          @limit      = clamp_limit(limit)
        end

        # @return [Result]
        def call
          channel = @connection.create_channel
          queue   = Store.queue_handle(channel, @queue)

          total = queue.message_count
          count = [@limit, total].min
          messages = count.positive? ? Store.peek(channel, @queue, count) : []

          Result.new(
            queue: @queue,
            total_messages: total,
            showing: messages.size,
            messages: messages,
          )
        ensure
          channel.close if channel&.open?
        end

        private

        def clamp_limit(value)
          n = value.to_i
          return DEFAULT_LIMIT if n <= 0
          return MAX_LIMIT if n > MAX_LIMIT

          n
        end
      end
    end
  end
end

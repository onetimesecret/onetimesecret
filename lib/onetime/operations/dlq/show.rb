# lib/onetime/operations/dlq/show.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'

module Onetime
  module Operations
    module Dlq
      # Show one message's full detail — the SINGLE implementation of the DLQ show
      # verb (epic #42 / D3). The `bin/ots queue dlq show <queue> --id/--index` CLI
      # and the colonel `GET /api/colonel/queues/dlq/:queue/messages/:message_id`
      # endpoint (#4343) are thin adapters over it.
      #
      # READ-ONLY: nothing is consumed. A lookup by id goes through
      # {Store.with_message}: a bounded scan ({Store::MAX_SCAN}) that returns
      # the deliveries ahead of the match as soon as it ends and leaves the
      # match unacked until this op closes its channel, so the queue keeps its
      # order. A lookup by index uses {Store.find_message}, which holds every
      # inspected message until the scan ends, then nack-requeues them all.
      # No {Onetime::ColonelAuditEvent} here (CONTRACT 4); the colonel adapter
      # records its own access observation for the payload it returns.
      #
      # Stateless, single `#call`, returns an immutable {Result}. `empty` is true
      # when the queue holds no messages (distinct from "found nothing matching"),
      # so the adapter can preserve the historic CLI's two different messages.
      class Show
        # @!attribute empty [r] Boolean the queue had zero messages
        # @!attribute message [r] Hash, nil the matched message detail
        # @!attribute scanned [r] Integer, nil deliveries the id lookup popped
        #   (nil on an index lookup)
        # @!attribute truncated [r] Boolean, nil the id lookup stopped at
        #   {Store::MAX_SCAN} with messages still behind it (nil on an index
        #   lookup)
        Result = Data.define(:found, :empty, :message, :scanned, :truncated) do
          def initialize(scanned: nil, truncated: nil, **)
            super
          end
        end

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param message_id [String, nil] match by message id …
        # @param index [Integer, nil] … or by 1-based position (caller supplies one).
        # @param max_scan [Integer] bound on an id lookup's scan; only the CLI
        #   passes more than {Store::MAX_SCAN}.
        def initialize(connection:, queue:, message_id: nil, index: nil, max_scan: Store::MAX_SCAN)
          @connection = connection
          @queue      = queue
          @message_id = message_id
          @index      = index
          @max_scan   = max_scan
        end

        # @return [Result]
        # @raise [Bunny::NotFound] when the queue is not declared
        def call
          channel = @connection.create_channel
          queue   = Store.queue_handle(channel, @queue)

          total = queue.message_count
          if total.zero?
            return Result.new(found: false, empty: true, message: nil, scanned: 0, truncated: false)
          end

          return show_by_id(channel) if @message_id

          message = Store.find_message(channel, @queue, nil, @index, total)
          Result.new(found: !message.nil?, empty: false, message: message)
        ensure
          channel.close if channel&.open?
        end

        private

        # The matched delivery is only projected, never settled: closing the
        # channel in #call returns it to its place in the queue.
        def show_by_id(channel)
          scan = Store.with_message(channel, @queue, @message_id, max_scan: @max_scan) do |delivery_info, properties, payload|
            Store.build_message_detail(delivery_info, properties, payload)
          end

          Result.new(
            found: scan.found,
            empty: false,
            message: scan.value,
            scanned: scan.scanned,
            truncated: scan.truncated,
          )
        end
      end
    end
  end
end

# lib/onetime/operations/dlq/show.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'

module Onetime
  module Operations
    module Dlq
      # Show one message's full detail — the SINGLE implementation of the DLQ show
      # verb (epic #42 / D3). The `bin/ots queue dlq show <queue> --id/--index` CLI
      # is a thin adapter over it.
      #
      # READ-ONLY: {Store.find_message} nack-requeues every inspected message, so
      # the queue is left untouched. No {Onetime::AdminAuditEvent} (CONTRACT 4).
      #
      # Stateless, single `#call`, returns an immutable {Result}. `empty` is true
      # when the queue holds no messages (distinct from "found nothing matching"),
      # so the adapter can preserve the historic CLI's two different messages.
      class Show
        # @!attribute empty [r] Boolean the queue had zero messages
        # @!attribute message [r] Hash, nil the matched message detail
        Result = Data.define(:found, :empty, :message)

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param message_id [String, nil] match by message id …
        # @param index [Integer, nil] … or by 1-based position (caller supplies one).
        def initialize(connection:, queue:, message_id: nil, index: nil)
          @connection = connection
          @queue      = queue
          @message_id = message_id
          @index      = index
        end

        # @return [Result]
        def call
          channel = @connection.create_channel
          queue   = Store.queue_handle(channel, @queue)

          total = queue.message_count
          if total.zero?
            return Result.new(found: false, empty: true, message: nil)
          end

          message = Store.find_message(channel, @queue, @message_id, @index, total)
          Result.new(found: !message.nil?, empty: false, message: message)
        ensure
          channel.close if channel&.open?
        end
      end
    end
  end
end

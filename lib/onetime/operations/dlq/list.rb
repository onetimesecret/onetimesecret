# lib/onetime/operations/dlq/list.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'

module Onetime
  module Operations
    module Dlq
      # Summarise every dead-letter queue — the SINGLE implementation of the DLQ
      # list-all verb (epic #42 / D3). The colonel endpoint (`GET
      # /api/colonel/queues/dlq`) and the `bin/ots queue dlq list` CLI (no queue
      # arg) are thin adapters over it.
      #
      # READ-ONLY: summarising queue depths mutates nothing, so — like the session
      # list / system read-outs — it records NO {Onetime::AdminAuditEvent}
      # (CONTRACT 4: audit is for mutations).
      #
      # Bounded by construction (CONTRACT 6): the set of DLQs is the fixed
      # {Store.all_dlq_names} allowlist, never an unbounded enumeration. Each queue
      # is inspected with a passive handle, so a queue that is configured but not
      # yet declared in the broker surfaces as `error: 'not declared'` (matching the
      # historic CLI) rather than aborting the whole listing.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class List
        # @!attribute dlqs [r] Array<Hash> per-queue summary rows
        # @!attribute total [r] Integer total messages across all DLQs
        Result = Data.define(:dlqs, :total)

        # @param connection [Object] an already-open Bunny-like connection. The op
        #   creates + closes its own channel off it (the connection's lifecycle
        #   belongs to the caller).
        def initialize(connection:)
          @connection = connection
        end

        # @return [Result]
        def call
          channel = @connection.create_channel

          dlqs = Store.all_dlq_names.map do |dlq_name|
            Store.summary_row(channel, dlq_name)
          rescue Bunny::NotFound
            # A passive declare of a not-yet-declared queue closes the channel
            # (AMQP spec), so reopen one for the next queue — exactly as the CLI did.
            channel = @connection.create_channel
            { queue: dlq_name, messages: 0, error: 'not declared' }
          end

          total = dlqs.sum { |row| row[:messages].to_i }
          Result.new(dlqs: dlqs, total: total)
        ensure
          channel.close if channel&.open?
        end
      end
    end
  end
end

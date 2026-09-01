# lib/onetime/operations/dlq/purge.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Dlq
      # Purge (permanently delete) every message from a dead-letter queue — the
      # SINGLE, audited implementation of the DLQ purge verb (epic #42 / D3 /
      # CONTRACT 4). The colonel endpoint (`POST
      # /api/colonel/queues/dlq/:queue/purge`) and the `bin/ots queue dlq purge`
      # CLI are thin adapters over it.
      #
      # This is the destructive DLQ verb — irreversible message loss. The `queue.purge`
      # call is byte-for-byte the historic CLI. The UI gates it behind
      # AdminConfirmDialog typed-confirmation (retype the queue name) and the CLI
      # behind a y/N prompt (both in the adapter, using the {dry_run} count); the op
      # itself just measures, purges, and audits.
      #
      # ## Audit (exactly once)
      #
      # A purge that removes ≥ 1 message records EXACTLY ONE
      # {Onetime::ColonelAuditEvent} — verb `queue.dlq.purge`, target the DLQ name,
      # detail the purged count. Purging an already-empty queue mutates nothing and
      # records NO event (the "only audit an actual change" rule).
      #
      # ## Dry run
      #
      # `dry_run: true` returns the count that WOULD be purged WITHOUT deleting
      # anything and WITHOUT recording an audit event — used to render the
      # count-in-scope in the confirm prompt/dialog before the live purge.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Purge
        include Onetime::AuditedFailure

        # Audit verb recorded for every purge that removes ≥ 1 message.
        AUDIT_VERB = 'queue.dlq.purge'

        # Irreversible verb over a broker connection, so a raise mid-purge (or a
        # broker error before it) is exactly what the trail must show. Records
        # one `result: :failure` and re-raises. `dry_run` is in the detail
        # because the success event is applied-path-only (a dry-run or empty
        # queue records nothing), so without it a failure has no readable
        # counterpart.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @queue },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol :success / :empty / :dry_run
        # @!attribute count [r] Integer messages measured in the queue
        # @!attribute purged [r] Integer messages actually removed (0 on dry-run/empty)
        Result = Data.define(:status, :queue, :count, :purged)

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param dry_run [Boolean] measure only — delete nothing, audit nothing.
        def initialize(connection:, queue:, actor:, dry_run: false)
          @connection = connection
          @queue      = queue
          @actor      = actor
          @dry_run    = dry_run
        end

        # @return [Result]
        def call
          channel = @connection.create_channel
          queue   = Store.queue_handle(channel, @queue)

          count = queue.message_count
          return Result.new(status: :dry_run, queue: @queue, count: count, purged: 0) if @dry_run
          return Result.new(status: :empty, queue: @queue, count: 0, purged: 0) if count.zero?

          queue.purge

          # Exactly one audit event per non-empty purge. The queue name is not
          # secret; never put message contents into detail.
          #
          # FAIL-CLOSED (#4333): the messages are gone from the broker and were
          # never mirrored anywhere, so the count in this event is the only
          # surviving fact about the purge. The dry-run path above returns
          # before this and stays unaffected.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :success,
            detail: { purged: count },
            fail_closed: true,
          )

          Result.new(status: :success, queue: @queue, count: count, purged: count)
        ensure
          channel.close if channel&.open?
        end
      end
    end
  end
end

# lib/onetime/operations/chores/budget.rb
#
# frozen_string_literal: true

module Onetime
  module Operations
    module Chores
      # Wall-clock budget for a synchronous chore run from the colonel console
      # (#4343).
      #
      # A console run answers an HTTP request that Caddy cuts off at its 15 s
      # `read_timeout`, so the run has to stop on its own well before that.
      # The record loops that run chores (HousekeepingJob.perform,
      # Billing::Operations::MaterializePlans#call) take this object as
      # `budget:` and ask {#exhausted?} before each record. They stop between
      # records, never inside one, so the work already done stays consistent
      # and the counts they report are exact for the records they reached.
      #
      # The loops only call `exhausted?`; anything answering it works as a
      # budget, which is how specs drive the cut-off without sleeping.
      #
      # ## A floor for the record loop
      #
      # Some runs do uninterruptible work before their loop: the entitlement
      # run pulls the Stripe catalog first. Measured from construction alone,
      # a slow pull would spend the whole budget and the loop would stop at
      # its first record, every time. So the loop also gets
      # `min_loop_seconds` from its FIRST check: the deadline is whichever is
      # later, construction + `seconds` or first check + `min_loop_seconds`.
      # A loop that starts right away (housekeeping) is unaffected; one that
      # starts late still makes progress, and the run overshoots `seconds` by
      # at most the floor rather than restarting the whole allowance.
      class Budget
        # @param seconds [Numeric] wall-clock allowance from construction
        # @param min_loop_seconds [Numeric] allowance guaranteed from the
        #   first {#exhausted?} check
        # @param clock [#call] monotonic seconds; injectable for specs
        def initialize(seconds, min_loop_seconds: 0, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @clock            = clock
          @started_at       = clock.call
          @deadline         = @started_at + seconds
          @min_loop_seconds = min_loop_seconds
          @loop_deadline    = nil
          @exhausted        = false
        end

        # Sticky: once the deadline has passed it stays exhausted, so every
        # later check in the same run agrees with the first one that tripped.
        #
        # @return [Boolean]
        def exhausted?
          return true if @exhausted

          now              = @clock.call
          @loop_deadline ||= now + @min_loop_seconds
          @exhausted       = now >= [@deadline, @loop_deadline].max
        end

        # @return [Integer] milliseconds since construction
        def elapsed_ms
          ((@clock.call - @started_at) * 1000).round
        end
      end
    end
  end
end

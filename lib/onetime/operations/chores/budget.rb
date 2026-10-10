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
      class Budget
        # @param seconds [Numeric] wall-clock allowance from construction
        # @param clock [#call] monotonic seconds; injectable for specs
        def initialize(seconds, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @clock      = clock
          @started_at = clock.call
          @deadline   = @started_at + seconds
          @exhausted  = false
        end

        # Sticky: once the deadline has passed it stays exhausted, so every
        # later check in the same run agrees with the first one that tripped.
        #
        # @return [Boolean]
        def exhausted?
          @exhausted ||= @clock.call >= @deadline
        end

        # @return [Integer] milliseconds since construction
        def elapsed_ms
          ((@clock.call - @started_at) * 1000).round
        end
      end
    end
  end
end

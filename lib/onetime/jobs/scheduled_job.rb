# lib/onetime/jobs/scheduled_job.rb
#
# frozen_string_literal: true

module Onetime
  module Jobs
    # Base class for scheduled jobs using rufus-scheduler
    #
    # Provides helper methods for common scheduling patterns and
    # standardized error handling. Subclasses must implement the
    # `.schedule(scheduler)` class method.
    #
    # Example:
    #   class MyJob < ScheduledJob
    #     def self.schedule(scheduler)
    #       every(scheduler, '1h') do
    #         # Job logic here
    #       end
    #     end
    #   end
    #
    # Scheduling patterns:
    #   - cron(scheduler, '0 0 * * *') { ... }  # Daily at midnight
    #   - every(scheduler, '1h') { ... }        # Every hour
    #   - every(scheduler, '30m') { ... }       # Every 30 minutes
    #
    class ScheduledJob
      class << self
        # Subclasses must implement this method to register with the scheduler
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        def schedule(scheduler)
          raise NotImplementedError, "#{name} must implement .schedule(scheduler)"
        end

        # Helper for cron-style scheduling
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param pattern [String] Cron pattern (e.g., '0 0 * * *')
        # @param options [Hash] Optional rufus-scheduler options
        def cron(scheduler, pattern, **options, &block)
          scheduler.cron(pattern, **options) do
            safely_execute(&block)
          end
        end

        # Helper for interval-based scheduling
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param interval [String] Interval (e.g., '1h', '30m', '5s')
        # @param options [Hash] Optional rufus-scheduler options
        def every(scheduler, interval, **options, &block)
          scheduler.every(interval, **options) do
            safely_execute(&block)
          end
        end

        # Helper for one-time delayed execution
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param delay [String] Delay (e.g., '10s', '5m')
        # @param options [Hash] Optional rufus-scheduler options
        def in_time(scheduler, delay, **options, &block)
          scheduler.in(delay, **options) do
            safely_execute(&block)
          end
        end

        # Helper for one-time execution at a specific time
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param time [Time, String] When to run (e.g., Time.now + 3600)
        # @param options [Hash] Optional rufus-scheduler options
        def at_time(scheduler, time, **options, &block)
          scheduler.at(time, **options) do
            safely_execute(&block)
          end
        end

        private

        # Execute block with error handling
        # Logs errors but doesn't re-raise to avoid crashing the scheduler
        def safely_execute
          yield
        rescue StandardError => e
          OT.le "[#{name}] Scheduled job failed: #{e.message}"
          OT.le e.backtrace.join("\n") if OT.debug?
        end
      end
    end
  end
end

# lib/onetime/jobs/scheduled_job.rb
#
# frozen_string_literal: true

require 'rufus-scheduler'
require_relative 'job_run'

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
        def cron(scheduler, pattern, **, &)
          job_ref = scheduler.cron(pattern, **) do |rufus_job, _time|
            safely_execute(rufus_job, &)
          end
          record_registration(scheduler, job_ref, kind: :cron, expression: pattern)
          job_ref
        end

        # Helper for interval-based scheduling
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param interval [String] Interval (e.g., '1h', '30m', '5s')
        # @param options [Hash] Optional rufus-scheduler options
        def every(scheduler, interval, **, &)
          job_ref = scheduler.every(interval, **) do |rufus_job, _time|
            safely_execute(rufus_job, &)
          end
          record_registration(scheduler, job_ref, kind: :every, expression: interval)
          job_ref
        end

        # Helper for one-time delayed execution
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param delay [String] Delay (e.g., '10s', '5m')
        # @param options [Hash] Optional rufus-scheduler options
        def in_time(scheduler, delay, **, &)
          job_ref = scheduler.in(delay, **) do |rufus_job, _time|
            safely_execute(rufus_job, &)
          end
          record_registration(scheduler, job_ref, kind: :in, expression: delay)
          job_ref
        end

        # Helper for one-time execution at a specific time
        # @param scheduler [Rufus::Scheduler] The scheduler instance
        # @param time [Time, String] When to run (e.g., Time.now + 3600)
        # @param options [Hash] Optional rufus-scheduler options
        def at_time(scheduler, time, **, &)
          job_ref = scheduler.at(time, **) do |rufus_job, _time|
            safely_execute(rufus_job, &)
          end
          record_registration(scheduler, job_ref, kind: :at, expression: time)
          job_ref
        end

        private

        # Seconds in an interval, parsed the same way `every` schedules it, so
        # a job deriving state from its own cadence can't disagree with the
        # scheduler about how long that cadence is.
        # @param interval [String, Numeric] Interval (e.g., '1h', '30m', 90)
        # @return [Integer]
        def interval_seconds(interval)
          Rufus::Scheduler.parse_duration(interval).to_i
        end

        # Execute block with error handling and record the run (#4343).
        # Logs errors but doesn't re-raise to avoid crashing the scheduler.
        #
        # Status: 'error' when the block raises or returns a report with
        # `:aborted` set (MaintenanceJob.with_stats returns its report, and an
        # aborted run is one the job itself logs as a failure); 'skipped' when
        # the report sets `:skipped`; 'partial' when the job's
        # `partial_failure` hook finds record-level failures in the report;
        # 'success' otherwise.
        #
        # The token `JobRun.started` returns goes to both `finished` calls, so
        # a run that overlaps a later one cannot overwrite its record.
        #
        # @param rufus_job [Rufus::Scheduler::Job, nil] the job rufus yields;
        #   its next_time is already the following occurrence (RepeatJob#trigger
        #   computes it before the work runs)
        def safely_execute(rufus_job = nil)
          job_id  = JobRun.job_id_for(self)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          token   = JobRun.started(job_id)

          result        = yield
          status, error = run_outcome(result)
          JobRun.finished(
            job_id,
            token: token,
            status: status,
            duration_ms: elapsed_ms(started),
            error: error,
            next_time: job_next_time(rufus_job),
          )
          result
        rescue StandardError => ex
          JobRun.finished(
            job_id,
            token: token,
            status: 'error',
            duration_ms: elapsed_ms(started),
            error: "#{ex.class}: #{ex.message}",
            next_time: job_next_time(rufus_job),
          )
          scheduler_logger.error "[#{name}] Scheduled job failed: #{ex.message}"
          scheduler_logger.error ex.backtrace.join("\n") if OT.debug?
        end

        # @return [Array(String, String|nil)] status and error text
        def run_outcome(result)
          return ['success', nil] unless result.is_a?(Hash)
          return ['error', "aborted: #{result[:aborted]}"] if result[:aborted]
          return ['skipped', nil] if result[:skipped]

          failure = partial_failure(result)
          return ['partial', failure] if failure

          ['success', nil]
        end

        # Record-level failures in a completed run, for jobs whose report
        # carries them (HousekeepingJob, EntitlementMaterializeJob). A run
        # that completed with failures used to record 'success' and clear
        # last_error. The base class knows no report shape, so it finds none.
        #
        # @param _report [Hash] the block's return value
        # @return [String, nil] short error text, or nil when nothing failed
        def partial_failure(_report)
          nil
        end

        # Record the registration. rufus returns the job id (a String) unless
        # the caller asked for the instance; spec doubles return nil.
        def record_registration(scheduler, job_ref, kind:, expression:)
          JobRun.register(
            self,
            kind: kind,
            expression: expression,
            next_time: registered_next_time(scheduler, job_ref),
          )
        end

        def registered_next_time(scheduler, job_ref)
          job = job_ref.is_a?(String) ? scheduler.job(job_ref) : job_ref
          job_next_time(job)
        rescue StandardError
          nil
        end

        def job_next_time(job)
          job.next_time if job.respond_to?(:next_time)
        end

        def elapsed_ms(started)
          ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
        end

        # Dedicated logger for scheduled jobs
        def scheduler_logger
          @scheduler_logger ||= Onetime.get_logger('Scheduler')
        end
      end
    end
  end
end

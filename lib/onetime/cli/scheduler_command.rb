# lib/onetime/cli/scheduler_command.rb
#
# frozen_string_literal: true

#
# CLI command for running the Rufus scheduler daemon
#
# Usage:
#   ots scheduler [options]
#
# Options:
#   -e, --environment ENV    Environment to run in (default: development)
#   -d, --daemonize          Run as daemon
#   -l, --log-level LEVEL    Log level: trace, debug, info, warn, error (default: info)
#

require 'rufus-scheduler'
require_relative '../jobs/scheduled_job'
require_relative '../jobs/registry'

module Onetime
  module CLI
    class SchedulerCommand < Command
        desc 'Start Rufus job scheduler'

        option :environment,
          type: :string,
          default: 'development',
          aliases: ['e'],
          desc: 'Environment to run in'
        option :daemonize,
          type: :boolean,
          default: false,
          aliases: ['d'],
          desc: 'Run as daemon'
        option :log_level,
          type: :string,
          default: 'info',
          aliases: ['l'],
          desc: 'Log level: trace, debug, info, warn, error'

        def call(_environment: 'development', daemonize: false, _log_level: 'info', **)
          # Set execution mode before boot so initializers can configure
          # process-specific settings (e.g., Sentry DSN for scheduler).
          OT.execution_mode = :scheduler

          boot_application!

          if daemonize
            daemonize_process
          end

          Onetime.app_logger.info('Starting Rufus scheduler daemon')

          # Create scheduler instance
          scheduler = Rufus::Scheduler.new

          # Captured before registration so every job registered by this boot
          # has registered_at >= started_at (the "scheduled" state, #4343).
          started_at = Familia.now.to_i

          # Load and register scheduled jobs
          load_scheduled_jobs(scheduler)

          job_count = scheduler.jobs.size
          Onetime::Jobs::JobRun.scheduler_started!(job_count: job_count, started_at: started_at)
          start_heartbeat(scheduler)

          # Set up signal handlers
          setup_signal_handlers(scheduler)

          Onetime.app_logger.info("Scheduler started with #{job_count} job(s)")
          log_scheduled_jobs(scheduler)

          # Block and run the scheduler
          scheduler.join
        end

      private

        def daemonize_process
          # Fork and detach
          Process.daemon(true, true)

          # Write PID file
          pid_path = ENV.fetch('SCHEDULER_PID_PATH', 'tmp/pids/scheduler.pid')
          FileUtils.mkdir_p(File.dirname(pid_path))
          File.write(pid_path, Process.pid)

          # Clean up PID file on exit
          at_exit { FileUtils.rm_f(pid_path) }
        end

        def load_scheduled_jobs(scheduler)
          # One discovery (Onetime::Jobs::Registry), shared with the colonel
          # jobs endpoint and `ots scheduler status`. Abstract intermediate
          # classes (e.g. MaintenanceJob) inherit the base .schedule() stub
          # that raises NotImplementedError; the registry filters them out.
          Onetime::Jobs::Registry.load_all!

          # Register each job with the scheduler
          Onetime::Jobs::Registry.concrete_classes.each do |job_class|
            job_class.schedule(scheduler)
            Onetime.app_logger.debug("Registered scheduled job: #{job_class.name}")
          end
        end

        # Liveness for the jobs catalog (#4343): a raw rufus job, not a
        # ScheduledJob, so it never lists itself. Without it "is the scheduler
        # alive?" has no answer when every job is disabled.
        def start_heartbeat(scheduler)
          scheduler.every(
            "#{Onetime::Jobs::JobRun::HEARTBEAT_INTERVAL}s",
            first_in: '1s',
            overlap: false,
          ) { Onetime::Jobs::JobRun.scheduler_heartbeat! }
        end

        def setup_signal_handlers(scheduler)
          %w[INT TERM].each do |signal|
            Signal.trap(signal) do
              Onetime.app_logger.info("Received #{signal}, shutting down scheduler...")
              scheduler.shutdown(:wait)
              exit 0
            end
          end

          # USR1 for status/reload
          Signal.trap('USR1') do
            Onetime.app_logger.info('Scheduler status:')
            log_scheduled_jobs(scheduler)
          end
        end

        def log_scheduled_jobs(scheduler)
          scheduler.jobs.each do |job|
            Onetime.app_logger.info(
              format(
                '  %s: next run at %s',
                job.id || job.original,
                job.next_time,
              ),
            )
          end
        end
    end

    register 'scheduler', SchedulerCommand
  end
end

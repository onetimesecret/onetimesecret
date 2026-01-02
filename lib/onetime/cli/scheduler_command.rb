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

module Onetime
  module CLI
    class SchedulerCommand < Command
        desc 'Start Rufus job scheduler'

        option :environment, type: :string, default: 'development', aliases: ['e'],
          desc: 'Environment to run in'
        option :daemonize, type: :boolean, default: false, aliases: ['d'],
          desc: 'Run as daemon'
        option :log_level, type: :string, default: 'info', aliases: ['l'],
          desc: 'Log level: trace, debug, info, warn, error'

        def call(_environment: 'development', daemonize: false, _log_level: 'info', **)
          boot_application!

          if daemonize
            daemonize_process
          end

          Onetime.app_logger.info('Starting Rufus scheduler daemon')

          # Create scheduler instance
          scheduler = Rufus::Scheduler.new

          # Load and register scheduled jobs
          load_scheduled_jobs(scheduler)

          # Set up signal handlers
          setup_signal_handlers(scheduler)

          Onetime.app_logger.info("Scheduler started with #{scheduler.jobs.size} job(s)")
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
          # Auto-discover scheduled job classes
          jobs_path = File.join(Onetime::HOME, 'lib', 'onetime', 'jobs', 'scheduled')
          return unless Dir.exist?(jobs_path)

          Dir.glob(File.join(jobs_path, '**', '*_job.rb')).each do |file|
            require file
          end

          # Find all scheduled job classes
          scheduled_classes = ObjectSpace.each_object(Class).select do |klass|
            klass.respond_to?(:schedule) && klass != Onetime::Jobs::ScheduledJob
          end

          # Register each job with the scheduler
          scheduled_classes.each do |job_class|
            job_class.schedule(scheduler)
            Onetime.app_logger.debug("Registered scheduled job: #{job_class.name}")
          end
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
            Onetime.app_logger.info(format(
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

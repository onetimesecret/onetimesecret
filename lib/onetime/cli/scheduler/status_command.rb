# lib/onetime/cli/scheduler/status_command.rb
#
# frozen_string_literal: true

#
# CLI reader for the scheduler's run records (#4343).
#
# Usage:
#   ots scheduler status                 # table
#   ots scheduler status --format json   # same data as GET /api/colonel/jobs
#
# Boots the application but never starts rufus: this reads the records the
# running scheduler writes. The projection is Onetime::Jobs::JobRun.catalog,
# the one the colonel jobs endpoint serves, so the shell and the console show
# the same rows. Read-only.
#
# Coexists with the `ots scheduler` daemon command (a leaf and a subcommand
# under one name, as `ots audit` / `ots audit list` do).

require 'json'
require 'onetime/jobs/registry'

module Onetime
  module CLI
    # Namespace for scheduler subcommands.
    module Scheduler
      FORMATS = %w[text json].freeze

      ROW_FORMAT = '%-26s %-13s %-11s %-19s  %-19s  %6s  %s'

      # Width of the error column in the text table; JSON carries the full text.
      ERROR_WIDTH = 60

      # Show every scheduled job with its last run, next due time and last error.
      class StatusCommand < Command
        desc 'Show scheduled jobs: last run, next due, last error, scheduler liveness'

        option :format,
          type: :string,
          default: 'text',
          aliases: ['f'],
          desc: "Output format: #{FORMATS.join(', ')}"

        def call(format: 'text', **)
          unless FORMATS.include?(format)
            warn "Unknown format '#{format}'. Use one of: #{FORMATS.join(', ')}"
            exit 1
          end

          boot_application!

          Onetime::Jobs::Registry.load_all!
          catalog = Onetime::Jobs::JobRun.catalog(Onetime::Jobs::Registry.entries)

          if format == 'json'
            puts JSON.pretty_generate(catalog)
          else
            display_text(catalog)
          end
        end

        private

        def display_text(catalog)
          puts scheduler_line(catalog['scheduler'])
          puts
          puts format(ROW_FORMAT, 'Job', 'State', 'Last status', 'Last run (UTC)', 'Next (UTC)', 'Runs', 'Error')
          catalog['jobs'].each { |row| puts job_line(row) }
        end

        def scheduler_line(sched)
          return 'Scheduler: not seen (no scheduler has started against this datastore)' unless sched['heartbeat_at']

          where = "#{sched['host'] || '?'} pid #{sched['pid'] || '?'}"
          age   = "heartbeat #{seconds_ago(sched['heartbeat_at'])} ago"
          if sched['alive']
            "Scheduler: alive (#{where}, #{age}, #{sched['job_count'].to_i} job(s))"
          else
            "Scheduler: NOT alive (#{where}, last #{age})"
          end
        end

        def job_line(row)
          format(
            ROW_FORMAT,
            row['job_id'],
            row['state'],
            row['last_status'],
            utc(row['last_started_at']),
            utc(row['next_time']),
            row['run_count'],
            truncate(row['last_error']),
          ).rstrip
        end

        def utc(epoch)
          return '-' if epoch.nil?

          Time.at(epoch).utc.strftime('%Y-%m-%d %H:%M:%S')
        end

        def seconds_ago(epoch)
          seconds = [Familia.now.to_i - epoch, 0].max
          return "#{seconds}s" if seconds < 120
          return "#{seconds / 60}m" if seconds < 7200

          "#{seconds / 3600}h"
        end

        def truncate(text)
          return '' if text.nil?
          return text if text.length <= ERROR_WIDTH

          "#{text[0, ERROR_WIDTH - 3]}..."
        end
      end
    end

    register 'scheduler status', Scheduler::StatusCommand
  end
end

# lib/onetime/jobs/scheduled/heartbeat_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'

module Onetime
  module Jobs
    module Scheduled
      # Simple heartbeat job for scheduler health monitoring
      #
      # Logs a message every minute to verify the scheduler is running.
      # Useful for development/debugging and as an example for other jobs.
      #
      # To disable in production, remove this file or check environment:
      #   return unless OT.conf.dig('jobs', 'heartbeat_enabled')
      #
      class HeartbeatJob < ScheduledJob
        def self.schedule(scheduler)
          every(scheduler, '1m', first_in: '5s') do
            stats = collect_stats
            OT.ld "[HeartbeatJob] #{Time.now.utc.iso8601} | " \
                  "secrets=#{stats[:secrets]} metadata=#{stats[:metadata]}"
          end
        end

        def self.collect_stats
          {
            secrets: Onetime::Secret.values.count,
            metadata: Onetime::Metadata.values.count
          }
        rescue StandardError => e
          OT.le "[HeartbeatJob] Failed to collect stats: #{e.message}"
          { secrets: -1, metadata: -1 }
        end
      end
    end
  end
end

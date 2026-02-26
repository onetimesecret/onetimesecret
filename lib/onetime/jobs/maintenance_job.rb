# lib/onetime/jobs/maintenance_job.rb
#
# frozen_string_literal: true

require_relative 'scheduled_job'

module Onetime
  module Jobs
    # Base class for scheduled maintenance jobs that perform data
    # consistency checks and repairs on Redis data structures.
    #
    # Provides shared configuration access, batch processing helpers,
    # and structured JSON report logging. All maintenance jobs ship
    # with `auto_repair: false` by default — enable only after
    # reviewing audit reports.
    #
    # Configuration (config.yaml):
    #   jobs:
    #     maintenance:
    #       enabled: true
    #       phantom_cleanup:
    #         enabled: true
    #         auto_repair: false
    #         batch_size: 500
    #         ...
    #
    # Example:
    #   class PhantomCleanupJob < MaintenanceJob
    #     def self.schedule(scheduler)
    #       return unless job_enabled?('phantom_cleanup')
    #       every(scheduler, job_interval('phantom_cleanup'), first_in: '2m') do
    #         with_stats('PhantomCleanupJob') { |report| cleanup(report) }
    #       end
    #     end
    #   end
    #
    class MaintenanceJob < ScheduledJob
      # Models with class-level instances sorted sets to maintain.
      # Each entry: [label, model_class, redis_prefix]
      INSTANCE_MODELS = [
        ['Customer',              'Onetime::Customer',              'customer'],
        ['Organization',          'Onetime::Organization',          'organization'],
        ['CustomDomain',          'Onetime::CustomDomain',          'custom_domain'],
        ['Receipt',               'Onetime::Receipt',               'receipt'],
        ['Secret',                'Onetime::Secret',                'secret'],
        ['Feedback',              'Onetime::Feedback',              'feedback'],
        ['OrganizationMembership', 'Onetime::OrganizationMembership', 'org_membership'],
      ].freeze

      # Participation sorted set patterns (target side of participates_in)
      PARTICIPATION_PATTERNS = [
        'organization:*:members',
        'organization:*:domains',
        'organization:*:receipts',
        'custom_domain:*:receipts',
      ].freeze

      # Default pipeline batch size for Redis EXISTS checks
      PIPELINE_BATCH = 50

      class << self
        private

        # Top-level maintenance config hash
        def maintenance_config
          OT.conf.dig('jobs', 'maintenance') || {}
        end

        # Per-job config hash (e.g., 'phantom_cleanup')
        def job_config(job_key)
          maintenance_config.dig(job_key) || {}
        end

        # Master + job-level enabled check
        def job_enabled?(job_key)
          maintenance_config['enabled'] == true &&
            job_config(job_key)['enabled'] == true
        end

        def auto_repair?(job_key)
          job_config(job_key)['auto_repair'] == true
        end

        def job_interval(job_key)
          job_config(job_key)['interval'] || '1h'
        end

        def job_cron(job_key)
          job_config(job_key)['cron'] || '0 4 * * *'
        end

        def sample_size(job_key)
          size = job_config(job_key)['sample_size'].to_i
          size > 0 ? size : 100
        end

        def batch_size(job_key)
          size = job_config(job_key)['batch_size'].to_i
          size > 0 ? size : 500
        end

        # Resolve a model class constant from its string name
        def resolve_model(class_name)
          class_name.split('::').reduce(Object) { |mod, name| mod.const_get(name) }
        end

        # Wrap job execution with timing and structured logging
        def with_stats(job_name)
          start_time = Time.now
          report = { job: job_name, started_at: start_time.utc.iso8601 }

          yield(report)

          report[:duration_ms] = ((Time.now - start_time) * 1000).round
          report[:completed_at] = Time.now.utc.iso8601
          log_report(report)
          report
        end

        def log_report(report)
          scheduler_logger.info "[#{report[:job]}] #{JSON.generate(report)}"
        end

        # Pipeline EXISTS checks for a batch of Redis keys.
        # Returns an array of booleans corresponding to each key.
        def pipeline_exists(redis, keys)
          return [] if keys.empty?

          results = redis.pipelined do |pipe|
            keys.each { |k| pipe.exists?(k) }
          end
          results
        end

        # Yield each member of a sorted set using ZSCAN (non-blocking).
        def zscan_each(redis, key, count: 100, &block)
          cursor = '0'
          loop do
            cursor, members = redis.zscan(key, cursor, count: count)
            members.each { |member, _score| block.call(member) }
            break if cursor == '0'
          end
        end
      end
    end
  end
end

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
    # Concurrency: rufus-scheduler does not prevent overlapping runs.
    # If a job takes longer than its interval, the next invocation
    # can start while the previous one is still scanning. The current
    # jobs tolerate this (SCAN is cursor-isolated, ZREM is idempotent),
    # but jobs with non-idempotent repair logic should add a Redis
    # lock (SET NX EX) around the critical section.
    #
    # Migration path: these batch jobs are candidates for systemd
    # timer + oneshot container execution. See ADR-002 and
    # docs/0228-scheduler-systemd-migration.md in ops-tools.
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

      # Hint for Redis SCAN/ZSCAN/HSCAN cursor iteration. Controls
      # roughly how many entries Redis returns per round-trip. Higher
      # values mean fewer round-trips but longer per-call blocking.
      SCAN_COUNT = 100

      # Familia stores model hashes at "prefix:identifier:suffix"
      # (e.g., "customer:abc123:object"). All key construction and
      # SCAN patterns must include this suffix.
      SUFFIX = Familia.default_suffix.to_s.freeze

      class << self
        private

        # Top-level maintenance config hash
        def maintenance_config
          OT.conf.dig('jobs', 'maintenance') || {}
        end

        # Per-job config hash (e.g., 'phantom_cleanup')
        def job_config(job_key)
          maintenance_config[job_key] || {}
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

        # Wrap job execution with timing and structured logging.
        # Uses monotonic clock for elapsed time (immune to NTP adjustments).
        def with_stats(job_name)
          mono_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          start_time = Time.now
          report     = { job: job_name, started_at: start_time.utc.iso8601 }

          yield(report)

          elapsed               = Process.clock_gettime(Process::CLOCK_MONOTONIC) - mono_start
          report[:duration_ms]  = (elapsed * 1000).round
          report[:completed_at] = Time.now.utc.iso8601
          log_report(report)
          report
        end

        def log_report(report)
          scheduler_logger.info "[#{report[:job]}] #{JSON.generate(report)}"
        end

        # Construct the backing dbkey for a model instance.
        # Familia stores model hashes at "prefix:identifier:object".
        def backing_key(prefix, identifier)
          "#{prefix}:#{identifier}:#{SUFFIX}"
        end

        # SCAN pattern matching only model instance dbkeys.
        # e.g., "customer:*:object" — excludes indexes and sorted sets.
        def model_scan_pattern(prefix)
          "#{prefix}:*:#{SUFFIX}"
        end

        # Extract the identifier from a full dbkey by stripping
        # the known prefix and suffix. Handles compound identifiers
        # containing the delimiter (e.g., OrganizationMembership keys).
        def extract_identifier(prefix, key)
          pfx = "#{prefix}:"
          sfx = ":#{SUFFIX}"
          return nil unless key.start_with?(pfx) && key.end_with?(sfx)

          key[pfx.length..-(sfx.length + 1)]
        end

        # Pipeline EXISTS checks for a batch of Redis keys.
        # Returns an array of booleans corresponding to each key.
        def pipeline_exists(redis, keys)
          return [] if keys.empty?

          redis.pipelined do |pipe|
            keys.each { |k| pipe.exists?(k) }
          end
        end

        # Map participation pattern suffix to the member's Redis prefix.
        # e.g., organization:*:members → customer, organization:*:domains → custom_domain
        def participation_member_prefix(pattern)
          case pattern
          when /members$/   then 'customer'
          when /domains$/   then 'custom_domain'
          when /receipts$/  then 'receipt'
          else 'unknown'
          end
        end

        # Yield each member of a sorted set using ZSCAN (non-blocking).
        def zscan_each(redis, key, count: SCAN_COUNT)
          cursor = '0'
          loop do
            cursor, members = redis.zscan(key, cursor, count: count)
            members.each { |member, _score| yield(member) }
            break if cursor == '0'
          end
        end
      end
    end
  end
end

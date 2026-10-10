# lib/onetime/jobs/job_run.rb
#
# frozen_string_literal: true

require 'socket'

module Onetime
  module Jobs
    # Run records for the rufus scheduler (#4343): what each scheduled job last
    # did, when it is next due, and whether the scheduler process is alive.
    #
    # Storage is one plain Redis hash per job (`jobs:run:<job_id>`) plus one for
    # the scheduler process (`jobs:scheduler`), written with HSET/HINCRBY and raw
    # string values. Not a Familia Horreum: `save` writes every declared field
    # (nil as "null") and JSON-encodes values, which breaks HINCRBY on the
    # counters and the partial updates the scheduler makes. No TTL: there is one
    # small hash per job class.
    #
    # Writers are best-effort. Each rescues StandardError, logs a warning and
    # returns nil, so a job never fails because its run record could not be
    # written. Readers raise: an unreadable store is an error for the caller to
    # report, not an empty catalog.
    #
    # Reads only touch known keys (one pipelined HGETALL batch). Nothing here
    # SCANs the keyspace.
    #
    # Times are UTC epoch seconds. Hashes returned by readers use string keys.
    module JobRun
      KEY_PREFIX         = 'jobs:run'
      SCHEDULER_KEY      = 'jobs:scheduler'
      STATUSES           = %w[running success error skipped].freeze
      NEVER              = 'never'
      MAX_ERROR_LENGTH   = 300
      HEARTBEAT_INTERVAL = 60 # seconds; SchedulerCommand refreshes heartbeat_at at this cadence
      ALIVE_WINDOW       = 3 * HEARTBEAT_INTERVAL

      # Catalog sort: plain scheduled jobs first, then maintenance jobs.
      GROUP_ORDER = { 'scheduled' => 0, 'maintenance' => 1 }.freeze

      INTEGER_FIELDS = %w[
        registered_at next_time last_started_at last_finished_at
        last_duration_ms run_count error_count scheduler_pid
      ].freeze

      SCHEDULER_INTEGER_FIELDS = %w[started_at heartbeat_at pid job_count].freeze

      extend self

      def dbclient = Familia.dbclient

      def key(job_id) = "#{KEY_PREFIX}:#{job_id}"

      # The one job_id rule, shared with Registry: class basename minus a
      # trailing "Job", snake_cased. HeartbeatJob -> heartbeat,
      # ParticipationGCJob -> participation_gc. Uses `#name` rather than `#to_s`
      # for classes so a class that overrides `name` is identified by it.
      #
      # @param klass_or_name [Module, String, Symbol]
      # @return [String, nil] nil when there is no name to derive from
      def job_id_for(klass_or_name)
        name = klass_or_name.is_a?(Module) ? klass_or_name.name : klass_or_name
        base = name.to_s.split('::').last.to_s.delete_suffix('Job')
        return nil if base.empty?

        base.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
      end

      # Written by ScheduledJob.cron/every/in_time/at_time right after rufus
      # accepts the job.
      def register(job_class, kind:, expression:, next_time: nil)
        job_id = job_id_for(job_class)
        return nil unless job_id

        dbclient.hset(
          key(job_id),
          stringify(
            'job_class' => job_class.name,
            'schedule_kind' => kind,
            'schedule_expression' => expression,
            'registered_at' => now,
            'next_time' => epoch(next_time),
            'scheduler_host' => host,
            'scheduler_pid' => Process.pid,
          ),
        )
        true
      rescue StandardError => ex
        write_failed(:register, job_id, ex)
      end

      def started(job_id)
        return nil unless job_id

        dbclient.multi do |tx|
          tx.hset(key(job_id), stringify('last_status' => 'running', 'last_started_at' => now))
          tx.hincrby(key(job_id), 'run_count', 1)
        end
        true
      rescue StandardError => ex
        write_failed(:started, job_id, ex)
      end

      # @param status [String] one of STATUSES other than 'running'
      # @param error [String, nil] stored email-obscured and truncated to
      #   MAX_ERROR_LENGTH; any other status clears the previous error
      # @param next_time [#to_i, nil] written only when given
      def finished(job_id, status:, duration_ms:, error: nil, next_time: nil)
        return nil unless job_id

        status = status.to_s
        raise ArgumentError, "unknown status #{status.inspect}" unless STATUSES.include?(status)

        fields              = {
          'last_status' => status,
          'last_finished_at' => now,
          'last_duration_ms' => duration_ms.to_i,
          'last_error' => error_text(error),
        }
        fields['next_time'] = epoch(next_time) unless next_time.nil?

        dbclient.multi do |tx|
          tx.hset(key(job_id), stringify(fields))
          tx.hincrby(key(job_id), 'error_count', 1) if status == 'error'
        end
        true
      rescue StandardError => ex
        write_failed(:finished, job_id, ex)
      end

      # @return [Hash, nil] string-keyed; integer fields coerced; nil when the
      #   job has no record
      def read(job_id)
        parse_run(dbclient.hgetall(key(job_id)))
      end

      # @return [Hash{String => Hash, nil}] one pipelined HGETALL batch
      def read_many(job_ids)
        ids = Array(job_ids)
        return {} if ids.empty?

        raws = dbclient.pipelined do |pipe|
          ids.each { |id| pipe.hgetall(key(id)) }
        end
        ids.zip(raws).to_h { |id, raw| [id, parse_run(raw)] }
      end

      # Called once per scheduler boot. `started_at` is captured by the caller
      # BEFORE jobs are registered, so every job registered during this boot
      # has registered_at >= started_at.
      def scheduler_started!(job_count:, started_at: now)
        dbclient.hset(
          SCHEDULER_KEY,
          stringify(
            'started_at' => started_at.to_i,
            'heartbeat_at' => now,
            'host' => host,
            'pid' => Process.pid,
            'job_count' => job_count.to_i,
          ),
        )
        true
      rescue StandardError => ex
        write_failed(:scheduler_started, 'scheduler', ex)
      end

      def scheduler_heartbeat!
        dbclient.hset(SCHEDULER_KEY, 'heartbeat_at', now.to_s)
        true
      rescue StandardError => ex
        write_failed(:scheduler_heartbeat, 'scheduler', ex)
      end

      # @return [Hash] string-keyed: alive, started_at, heartbeat_at, host,
      #   pid, job_count. Fields are nil (alive false) when no scheduler has
      #   ever written the record.
      def scheduler
        parse_scheduler(dbclient.hgetall(SCHEDULER_KEY))
      end

      # The one projection the colonel endpoint and `bin/ots scheduler status`
      # share. One pipelined round trip for every job record plus the
      # scheduler record.
      #
      # @param entries [Array<Hash>] Registry.entries rows
      #   ('job_id', 'job_class', 'group')
      # @return [Hash] { 'scheduler' => Hash, 'jobs' => Array<Hash> }
      def catalog(entries)
        ids  = entries.map { |entry| entry['job_id'] }
        raws = dbclient.pipelined do |pipe|
          ids.each { |id| pipe.hgetall(key(id)) }
          pipe.hgetall(SCHEDULER_KEY)
        end

        sched = parse_scheduler(raws.pop)
        rows  = entries.zip(raws).map { |entry, raw| catalog_row(entry, parse_run(raw), sched) }
        rows.sort_by! { |row| [GROUP_ORDER.fetch(row['group'], GROUP_ORDER.size), row['job_id']] }

        { 'scheduler' => sched, 'jobs' => rows }
      end

      # 'scheduled'     registered during the current scheduler boot
      # 'not_scheduled' the scheduler booted but this job did not register
      #                 (disabled in config, or registered by an older boot)
      # 'unknown'       no scheduler has ever written its record
      def state_for(run, sched)
        started_at = sched && sched['started_at']
        return 'unknown' unless started_at

        registered_at = run && run['registered_at']
        registered_at && registered_at >= started_at ? 'scheduled' : 'not_scheduled'
      end

      def catalog_row(entry, run, sched)
        state = state_for(run, sched)
        run ||= {}

        {
          'job_id' => entry['job_id'],
          'job_class' => entry['job_class'],
          'group' => entry['group'],
          'state' => state,
          'schedule_kind' => run['schedule_kind'],
          'schedule_expression' => run['schedule_expression'],
          # A job the current boot did not schedule has no next run; the stored
          # value belongs to an earlier boot.
          'next_time' => state == 'not_scheduled' ? nil : run['next_time'],
          'registered_at' => run['registered_at'],
          'last_status' => run['last_status'] || NEVER,
          'last_started_at' => run['last_started_at'],
          'last_finished_at' => run['last_finished_at'],
          'last_duration_ms' => run['last_duration_ms'],
          'last_error' => run['last_error'],
          'run_count' => run['run_count'].to_i,
          'error_count' => run['error_count'].to_i,
        }
      end

      def parse_run(raw)
        return nil if raw.nil? || raw.empty?

        raw.each_with_object({}) do |(field, value), out|
          out[field] = INTEGER_FIELDS.include?(field) ? integer(value) : blank_to_nil(value)
        end
      end

      def parse_scheduler(raw)
        ints      = SCHEDULER_INTEGER_FIELDS.to_h { |field| [field, integer(raw&.[](field))] }
        heartbeat = ints['heartbeat_at']

        {
          'alive' => !heartbeat.nil? && (now - heartbeat) <= ALIVE_WINDOW,
          'started_at' => ints['started_at'],
          'heartbeat_at' => heartbeat,
          'host' => blank_to_nil(raw&.[]('host')),
          'pid' => ints['pid'],
          'job_count' => ints['job_count'],
        }
      end

      # Error text from a job is free text. It can carry a customer address
      # (an exception message interpolating an email) or a credential
      # (redis-client appends its server URL, userinfo included, to every
      # ConnectionError). It is stored with no TTL and served by an unaudited
      # read, so both are masked before it is written: URI userinfo first,
      # so the email pass never sees `user:pass@host` as an address.
      def error_text(error)
        return '' if error.nil?

        Onetime::Utils.obscure_email(Onetime::Utils.redact_uris_in_text(error.to_s))[0, MAX_ERROR_LENGTH]
      end

      def write_failed(operation, job_id, ex)
        Onetime.get_logger('Scheduler').warn(
          "[JobRun] #{operation} failed for #{job_id}: #{ex.class}: #{ex.message}",
        )
        nil
      rescue StandardError
        nil
      end

      def now = Familia.now.to_i

      # nil stays nil (written as '' so a stale value is cleared, read back as
      # nil). EoTime/Time/Integer all answer #to_i.
      def epoch(time) = time.nil? ? nil : time.to_i

      def host = Socket.gethostname

      def integer(value)
        return nil if value.nil? || value.to_s.empty?

        Integer(value.to_s, 10, exception: false)
      end

      def blank_to_nil(value)
        value.nil? || value.to_s.empty? ? nil : value
      end

      def stringify(fields)
        fields.to_h { |field, value| [field.to_s, value.to_s] }
      end
    end
  end
end

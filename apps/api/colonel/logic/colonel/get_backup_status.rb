# apps/api/colonel/logic/colonel/get_backup_status.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Read the ots-backup v1 status hashes published beside this application.
      #
      # This endpoint deliberately performs only HGETALL reads against the eight
      # known job hashes. It never scans or writes the datastore, and it does not
      # read the package's `_check` hash. A malformed or partial external record
      # is represented with null fields rather than being allowed to break the
      # Colonel response.
      class GetBackupStatus < ColonelAPI::Logic::Base
        SCHEMAS = { response: 'backupStatus' }.freeze

        JOBS               = %w[pg valkey prune ship].freeze
        STATUS_KEY_PREFIX  = 'ots:backup:status:'
        EVENTS             = %w[start ok fail].freeze
        SCHEDULED_STATES   = %w[enabled disabled unknown].freeze
        PRUNE_MODES        = %w[report delete].freeze
        MAX_TIMESTAMP      = 8_640_000_000_000 # JavaScript Date's maximum, in seconds.
        MAX_TEXT_BYTES     = 4_096

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          success_data
        end

        def success_data
          {
            record: {},
            details: {
              timestamp: Familia.now.to_i,
              jobs: JOBS.map { |job| job_status(job) },
            },
          }
        end

        private

        def job_status(job)
          latest  = read_hash(status_key(job))
          last_ok = sanitize_record(read_hash(last_ok_key(job)), job) if latest.any?
          {
            job: job,
            configured: latest.any?,
            latest: latest.any? ? sanitize_record(latest, job) : nil,
            # A stray or malformed last_ok is not evidence of a successful run.
            # In particular, freshness must never trust an event other than `ok`.
            last_ok: last_ok&.fetch(:event) == 'ok' ? last_ok : nil,
          }
        end

        def status_key(job)
          "#{STATUS_KEY_PREFIX}#{job}"
        end

        def last_ok_key(job)
          "#{status_key(job)}:last_ok"
        end

        def read_hash(key)
          # HGETALL returns an empty Hash only when this known status key is
          # missing. Permission, wrong-type, and transport failures propagate so
          # the HTTP endpoint (and its panel) reports a real read error instead
          # of falsely claiming the backup is not configured.
          Familia.dbclient.hgetall(key)
        end

        def sanitize_record(raw, job)
          {
            event: enum_value(raw['event'], EVENTS),
            ts: timestamp_value(raw['ts']),
            host: text_value(raw['host']),
            unit: text_value(raw['unit']),
            job: text_value(raw['job']) == job ? job : nil,
            file: text_value(raw['file']),
            bytes: decimal_or_empty(raw['bytes']),
            sha256: sha256_or_empty(raw['sha256']),
            mode: enum_or_empty(raw['mode'], PRUNE_MODES),
            removed: decimal_or_empty(raw['removed']),
            candidates: decimal_or_empty(raw['candidates']),
            duration_secs: decimal_or_empty(raw['duration_secs']),
            error: text_value(raw['error'], max_bytes: nil),
            version: text_value(raw['version'], max_bytes: 128),
            scheduled: enum_value(raw['scheduled'], SCHEDULED_STATES),
          }
        end

        def timestamp_value(value)
          return unless value.is_a?(String) && value.match?(/\A\d+\z/)

          timestamp = value.to_i
          timestamp if timestamp <= MAX_TIMESTAMP
        end

        def enum_value(value, allowed)
          value if value.is_a?(String) && allowed.include?(value)
        end

        def enum_or_empty(value, allowed)
          return '' if value == ''

          enum_value(value, allowed)
        end

        def decimal_or_empty(value)
          return '' if value == ''
          return unless value.is_a?(String) && value.match?(/\A\d+\z/) && value.length <= 20

          value
        end

        def sha256_or_empty(value)
          return '' if value == ''
          return unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/i)

          value
        end

        def text_value(value, max_bytes: MAX_TEXT_BYTES)
          return unless value.is_a?(String)
          return unless value.ascii_only? && !value.match?(/[\r\n]/)
          return if max_bytes && value.bytesize > max_bytes

          value
        end
      end
    end
  end
end

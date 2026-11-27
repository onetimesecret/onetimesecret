# migrations/2026-11-27/20261127_01_migrate_secret_activity_legacy.rb
#
# frozen_string_literal: true

#
# Move each organization's pre-coalescing Secret Activity trail into the
# member partition.
#
# Before v0.27.0 every organization's trail was one sorted set,
# secret_activity_events, whose members are event JSON with a nonce. The
# trail is now stored as partitions of event ids with detail, count and
# first-seen hashes (Organization::Features::SecretActivity). The
# application migrates an organization's legacy set on its first write or
# read, so this migration is not required for correctness. It moves every
# organization at once, so the member cap (SECRET_ACTIVITY_MAX_EVENTS)
# applies to all existing history straight away instead of waiting for
# each organization's next write or read.
#
# Each legacy row becomes id "l1:<nonce>" with count 1 and its JSON as the
# detail; the member cap then removes the oldest rows over the cap, and the
# legacy key is deleted. It runs as one Lua script per organization, so it
# is atomic and a rerun is a no-op.
#
# Usage:
#   bin/ots migrate 20261127_01_migrate_secret_activity_legacy           # Preview
#   bin/ots migrate --run 20261127_01_migrate_secret_activity_legacy     # Execute
#
require 'familia/migration'

module Onetime
  module Migrations
    # Migrate organizations' legacy secret_activity_events sets.
    class MigrateSecretActivityLegacy < Familia::Migration::Base
      self.migration_id = '20261127_01_migrate_secret_activity_legacy'
      self.description  = 'Move legacy Secret Activity trails into the member partition'
      self.dependencies = []

      PROGRESS_STEP = 250

      def prepare
        @model_class = Onetime::Organization
      end

      def migration_needed?
        @model_class.instances.each do |objid|
          org = @model_class.load(objid)
          return true if org&.secret_activity_events&.exists?
        rescue StandardError => ex
          error "migration_needed? error for #{objid}: #{ex.message}"
        end

        false
      end

      def migrate
        run_mode_banner

        total     = @model_class.instances.count
        processed = 0

        @model_class.instances.each do |objid|
          process_organization(objid)
        rescue StandardError => ex
          track_stat(:errors)
          error "Error processing organization #{objid}: #{ex.message}"
        ensure
          processed += 1
          report_progress(processed, total)
        end

        print_summary do |mode|
          @stats.each { |key, value| info "  #{key}: #{value}" }
          info ''
          info(mode == :dry_run ? 'Re-run with --run to apply changes.' : 'Legacy Secret Activity migrated.')
        end

        true
      end

      private

      def process_organization(objid)
        org = @model_class.load(objid)
        legacy_rows = org&.secret_activity_events&.element_count.to_i
        if legacy_rows.zero?
          track_stat(:nothing_to_migrate)
          return
        end

        if dry_run?
          track_stat(:would_migrate)
          track_stat(:would_migrate_rows, legacy_rows)
          info "[DRY RUN] would migrate #{legacy_rows} legacy rows for #{objid}"
          return
        end

        track_stat(:migrated)
        track_stat(:migrated_rows, org.migrate_legacy_secret_activity!)
      end

      def report_progress(processed, total)
        return unless total >= PROGRESS_STEP
        return unless (processed % PROGRESS_STEP).zero? || processed == total

        breakdown = @stats.map { |k, v| "#{k}=#{v}" }.join(', ')
        info "Progress: #{processed}/#{total} (#{breakdown})"
      end
    end
  end
end

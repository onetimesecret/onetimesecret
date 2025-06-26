#!/usr/bin/env ruby
# migrate/example_secret_stats_migration.rb
#
# Secret Statistics Migration Example
#
# Purpose: Demonstrates ModelMigration usage by adding view_count field to secrets
# This is an example migration showing how to use the ModelMigration base class
#
# Usage:
#   ruby -I./lib migrate/example_secret_stats_migration.rb --dry-run  # Preview changes
#   ruby -I./lib migrate/example_secret_stats_migration.rb --run      # Execute migration
#
#   bin/ots migrate example_secret_stats_migration.rb

require 'onetime/model_migration'

module Onetime
  class Migration < ModelMigration
    def prepare
      @model_class = V2::Secret
      @batch_size = 2000  # Secrets might be more numerous than customers
    end

    def process_record(obj)
      # Skip expired or burned secrets
      if obj.state == 'burned'
        track_stat(:skipped_burned)
        return
      end

      # Check if migration is needed for this record
      needs_view_count = obj.view_count.to_s.empty?
      needs_last_viewed = obj.last_viewed.to_s.empty? && obj.viewed?

      return unless needs_view_count || needs_last_viewed

      # Log what we're updating
      updates = []
      updates << "view_count=0" if needs_view_count
      updates << "last_viewed" if needs_last_viewed

      debug("Updating secret #{obj.key}: #{updates.join(', ')}")

      # Apply updates if in actual run mode
      for_realsies_this_time? do
        if needs_view_count
          obj.view_count = 0
          track_stat(:view_count_initialized)
        end

        if needs_last_viewed && obj.viewed?
          # Set to updated time if we don't have better data
          obj.last_viewed = obj.updated || obj.created
          track_stat(:last_viewed_set)
        end

        obj.save
        track_stat(:records_updated)
      end
    end

    def migration_needed?
      # Check a sample of records to see if migration is needed
      sample_size = 10
      sample_keys = @redis_client.scan(0, match: @scan_pattern, count: sample_size)[1]

      sample_keys.each do |key|
        record_data = get_record_data(key)
        if record_data['view_count'].to_s.empty?
          info("Found records missing view_count field")
          return true
        end
      end

      info("Sample check shows all records have required fields")
      false
    end
  end
end

# If this script is run directly
if __FILE__ == $0
  OT.boot! :cli
  exit(Onetime::Migration.run(run: ARGV.include?('--run')) ? 0 : 1)
end

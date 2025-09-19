# lib/onetime/cli/migrate_redis_data_command.rb

module Onetime
  class MigrateRedisDataCommand < Onetime::CLI
    def init
      # Set environment variable to bypass startup warnings for this command
      ENV['SKIP_LEGACY_DATA_CHECK'] = 'true'

      # Call parent init which boots the application
      super
    end

    def migrate_redis_data
      puts "\n🔄 Redis Legacy Data Migration Tool"
      puts "=" * 50

      # Reset env var to allow detection to run again
      ENV.delete('SKIP_LEGACY_DATA_CHECK')

      # First, detect legacy data
      puts "Scanning for legacy data distribution..."
      require_relative '../initializers/detect_legacy_data'

      # Include the detection methods
      extend Onetime::Initializers

      # Override skip check for this command - we always want to scan during migration
      def skip_legacy_data_check?; false; end

      legacy_data = detect_legacy_data

      if legacy_data.empty?
        puts "\n✅ No legacy data detected. All data appears to be in the correct databases."
        puts "Migration not needed."
        return
      end

      puts "\n📊 Legacy Data Found:"
      total_keys = 0
      migration_plan = []

      legacy_data.each do |model, locations|
        puts "\n  #{model.capitalize} model:"
        locations.each do |location|
          total_keys += location[:key_count]
          migration_plan << {
            model: model,
            from_db: location[:database],
            to_db: location[:expected_database],
            key_count: location[:key_count],
            pattern: "#{model}:*"
          }

          puts "    📍 Database #{location[:database]}: #{location[:key_count]} keys"
          puts "    📋 Sample keys: #{location[:sample_keys].join(', ')}" if location[:sample_keys].any?
        end
      end

      puts "\n📋 Migration Preview:"
      migration_plan.each do |plan|
        puts "  • #{plan[:key_count]} #{plan[:model]} keys: DB #{plan[:from_db]} → DB #{plan[:to_db]}"
      end
      puts "
  Total keys to migrate: #{total_keys}"

      if argv.include?('--dry-run') || !global.run
        puts "\n🔍 DRY RUN MODE - No changes will be made"
        puts "To execute the migration, run with --run flag"
        return
      end

      # Confirm before proceeding
      puts "\n⚠️  WARNING: This will move data between Redis databases."
      puts "Make sure you have a backup before proceeding."
      print "\nContinue with migration? (yes/no): "

      response = STDIN.gets.chomp.downcase
      unless ['yes', 'y'].include?(response)
        puts "Migration cancelled."
        return
      end

      # Execute migration
      puts "\n🚀 Starting migration..."

      migration_plan.each do |plan|
        puts "\n📦 Migrating #{plan[:model]} data (#{plan[:key_count]} keys)..."
        puts "   From: DB #{plan[:from_db]} → To: DB #{plan[:to_db]}"

        source_uri = URI.parse(Familia.uri.to_s)
        target_uri = URI.parse(Familia.uri.to_s)
        source_uri.db = plan[:from_db]
        target_uri.db = plan[:to_db]

        moved_count = 0
        begin
          Familia::Tools.move_keys(plan[:pattern], source_uri, target_uri) do |idx, type, key, ttl|
            moved_count = idx + 1
            if global.verbose > 0
              puts "   #{moved_count.to_s.rjust(4)} (#{type.to_s.rjust(6)}, #{ttl.to_s.rjust(4)}): #{key}"
            else
              print "\r   Moved #{moved_count} keys"
            end
          end

          puts "\n   ✅ Successfully migrated #{moved_count} #{plan[:model]} keys"

        rescue => ex
          puts "\n   ❌ Error migrating #{plan[:model]} data: #{ex.message}"
          OT.le "Migration error for #{plan[:model]}: #{ex.message}"
          OT.ld ex.backtrace.join("\n")
        end
      end

      puts "\n🎉 Migration completed!"
      puts "\n📝 Next steps:"
      puts "1. Restart your application to verify everything works correctly"
      puts "2. Remove any REDIS_DBS_* environment variables if you were using them"
      puts "3. Your configuration now uses database 0 for all models (default)"

      # Clean up migration flags
      puts "\n🧹 Cleaning up migration flags..."
      legacy_data.each do |model, locations|
        locations.each do |location|
          begin
            client = Familia.dbclient(location[:database])
            flag_key = Familia.join(['ots', 'migration_needed', model, "db_#{location[:database]}"])
            client.del(flag_key)
            puts "   Removed migration flag: #{flag_key}"
          rescue => ex
            OT.ld "Could not remove migration flag for #{model}: #{ex.message}"
          end
        end
      end

      puts "\n✅ All done! Your Redis data has been migrated to database 0."
    end
  end
end

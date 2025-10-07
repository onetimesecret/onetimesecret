# lib/onetime/cli/migrate_redis_data_command.rb

require_relative '../redis_key_migrator'

module Onetime
  class MigrateRedisDataCommand < Onetime::CLI
    def init
      # Set environment variable to bypass startup warnings for this command
      ENV['SKIP_LEGACY_DATA_CHECK'] = 'true'

      # Call parent init which boots the application
      super
    end

    def migrate_redis_data
      # Show help if requested
      return if show_usage_help

      puts "\nRedis Data Consolidation Tool"
      puts '=' * 50

      # Reset env var to allow detection to run again
      ENV.delete('SKIP_LEGACY_DATA_CHECK')

      # Enable migration mode to find ALL data not in DB 0
      ENV['MIGRATION_MODE'] = 'true'

      # First, detect legacy data
      puts 'Scanning for legacy data distribution...'
      require_relative '../initializers/detect_legacy_data'

      # Include the detection methods
      extend Onetime::Initializers

      # Override skip check for this command - we always want to scan during migration
      def skip_legacy_data_check? = false

      detection_result = detect_legacy_data
      legacy_data      = detection_result[:legacy_locations] || detection_result

      if legacy_data.empty?
        puts <<~MESSAGE

          ✅ No legacy data detected. All data appears to be in the correct databases.
          Migration not needed.

        MESSAGE
        return
      end

      puts "\nLegacy Data Found:"
      total_keys     = 0
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
            pattern: "#{model}:*",
          }

          puts "    Database #{location[:database]}: #{location[:key_count]} keys"
          puts "    Sample keys: #{location[:sample_keys].join(', ')}" if location[:sample_keys].any?
        end
      end

      puts "\nMigration Preview:"
      migration_plan.each do |plan|
        puts "  • #{plan[:model]} keys: DB #{plan[:from_db]} → DB #{plan[:to_db]} (#{plan[:key_count]}+ detected)"
      end
      puts <<~MESSAGE

        Note: Detection counts are samples. Actual migration processes all matching keys per database.
        Use 'redis-cli info keyspace' for complete database statistics.
      MESSAGE

      # Check for --show-commands option first (before dry run check)
      if option.show_commands
        puts "\n" + ('=' * 60)
        puts 'REDIS CLI COMMANDS (for manual execution)'
        puts '=' * 60

        migration_plan.each do |plan|
          puts "\n## #{plan[:model].capitalize} migration (#{plan[:key_count]} keys)"
          puts "## From: DB #{plan[:from_db]} → DB #{plan[:to_db]}"

          source_uri    = URI.parse(Familia.uri.to_s)
          target_uri    = URI.parse(Familia.uri.to_s)
          source_uri.db = plan[:from_db]
          target_uri.db = plan[:to_db]

          migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri)
          commands = migrator.generate_cli_commands(plan[:pattern])

          puts "\nStrategy: #{commands[:strategy].to_s.upcase}"
          puts "\n### Key Discovery"
          commands[:discovery].each { |cmd| puts cmd }

          puts "\n### Migration Commands"
          commands[:migration].each { |cmd| puts cmd }

          puts "\n### Verification Commands"
          commands[:verification].each { |cmd| puts cmd }

          puts "\n### Cleanup Commands (Optional - Use with caution!)"
          commands[:cleanup].each { |cmd| puts cmd }

          puts "\n" + ('-' * 60)
        end

        puts <<~MESSAGE

          ℹ️  Commands generated above. Copy and paste to execute manually.
          ⚠️  Always verify migration success before running cleanup commands!

        MESSAGE
        return
      end

      # Dry run check (only if not showing commands)
      unless option.run
        puts <<~MESSAGE

          DRY RUN MODE - No changes will be made
          To execute the consolidation, run with --run flag

        MESSAGE
        return
      end

      # Check for non-interactive mode
      auto_confirm = option.yes || !$stdin.tty?

      if auto_confirm
      puts <<~MESSAGE
        ⚠️  Auto-confirmed: Consolidation will proceed (non-TTY or --yes flag detected)
      MESSAGE
      else
        # Confirm before proceeding
        puts <<~WARNING

          ⚠️  WARNING: This will move data between Redis databases.
          Make sure you have a backup before proceeding.

        WARNING

        print 'Continue with consolidation? (yes/no): '
        response = STDIN.gets.chomp.downcase

        return puts('Consolidation cancelled.') unless %w[yes y].include?(response)
      end

      # Execute consolidation
      puts "\nStarting consolidation..."

      migration_plan.each do |plan|
        puts "\nConsolidating #{plan[:model]} data (#{plan[:key_count]} keys)..."
        puts "   From: DB #{plan[:from_db]} → To: DB #{plan[:to_db]}"

        source_uri    = URI.parse(Familia.uri.to_s)
        target_uri    = URI.parse(Familia.uri.to_s)
        source_uri.db = plan[:from_db]
        target_uri.db = plan[:to_db]

        begin
          # Configure migration options
          migration_options = {
            batch_size: parse_batch_size,
            copy_mode: true,  # Keep keys in source for safety
            timeout: 5000,
            progress_interval: 50,
          }

          migrator = Onetime::RedisKeyMigrator.new(source_uri, target_uri, migration_options)

          # Show CLI commands in verbose mode
          if global.verbose > 0
            puts "   Strategy: #{migrator.send(:determine_migration_strategy).to_s.upcase}"
            commands = migrator.generate_cli_commands(plan[:pattern])
            puts '   Manual CLI commands:'
            puts "     Discovery: #{commands[:discovery][1]}" if commands[:discovery][1]
            puts "     Migration: #{commands[:migration][1]}" if commands[:migration][1]
            puts ''
          end

          # Track progress and statistics
          moved_count      = 0
          last_report_time = Time.now

          statistics = migrator.migrate_keys(plan[:pattern]) do |phase, idx, type, key, ttl|
            case phase
            when :discovery
              if global.verbose > 0
                print "\r   Discovering keys: #{idx}"
              end
            when :migrate
              moved_count  = idx + 1
              current_time = Time.now

              if global.verbose > 0
                puts "   #{moved_count.to_s.rjust(4)} (#{type.to_s.rjust(10)}, #{ttl.to_s.rjust(4)}): #{key}"
              elsif current_time - last_report_time > 0.5  # Report every 500ms
                print "\r   Migrated #{moved_count} keys"
                last_report_time = current_time
              end
            end
          end

          # Final progress update
          print "\r   Migrated #{statistics[:migrated_keys]} keys"

          # Report migration statistics
          duration = statistics[:end_time] - statistics[:start_time]
          strategy = statistics[:strategy_used]

          puts "\n   ✅ Successfully migrated #{statistics[:migrated_keys]} #{plan[:model]} keys"
          puts "      Strategy: #{strategy.to_s.upcase}, Duration: #{'%.2f' % duration}s"

          if statistics[:failed_keys] > 0
            puts "      ⚠️  #{statistics[:failed_keys]} keys failed to migrate"
          end

          if global.verbose > 0 && statistics[:errors].any?
            puts '      Errors encountered:'
            statistics[:errors].each { |error| puts "        • #{error[:context]}: #{error[:error]}" }
          end
        rescue StandardError => ex
          puts "\n   ❌ Error migrating #{plan[:model]} data: #{ex.message}"
          OT.le "Migration error for #{plan[:model]}: #{ex.message}"
          OT.ld ex.backtrace.join("\n")
        end
      end

      puts <<~MESSAGE

         Migration completed!

        Next steps:
        1. Restart your application to verify everything works correctly
        2. Remove any REDIS_DBS_* environment variables if you were using them
        3. Your configuration now uses database 0 for all models (default)

      MESSAGE

      # Clean up migration flags
      puts "\n🧹 Cleaning up migration flags..."
      legacy_data.each do |model, locations|
        locations.each do |location|
            client   = Familia.dbclient(location[:database])
            flag_key = Familia.join(['ots', 'migration_needed', model, "db_#{location[:database]}"])
            client.del(flag_key)
            puts "   Removed migration flag: #{flag_key}"
        rescue StandardError => ex
            OT.ld "Could not remove migration flag for #{model}: #{ex.message}"
        end
      end

      # Clean up environment
      ENV.delete('MIGRATION_MODE')

      puts "\nAll done! Your Redis data has been migrated to database 0."
    end

    private

    def parse_batch_size
      if option.batch_size
        size = option.batch_size.to_i
        if size > 0 && size <= 10_000
          return size
        else
          raise "Invalid batch size: #{option.batch_size}. Must be between 1 and 10,000."
        end
      end
      100  # Default batch size
    end

    def show_usage_help
      if option.help
        puts <<~USAGE

          Redis Data Consolidation Tool

          Usage:
            bin/ots consolidate-redis-models [options]

          Options:
            --run                 Execute the consolidation (required for actual operation)
            --dry-run             Show what would be consolidated without executing
            --show-commands       Generate redis-cli commands for manual execution
            --yes                 Auto-confirm consolidation (non-interactive mode)
            --batch-size=N        Set batch size for consolidation (default: 100, max: 10000)
            --verbose             Show detailed progress and CLI commands
            --help, -h            Show this help message

          Examples:
            # Preview consolidation
            bin/ots consolidate-redis-models

            # Execute consolidation with confirmation
            bin/ots consolidate-redis-models --run

            # Generate manual CLI commands
            bin/ots consolidate-redis-models --show-commands

            # Execute with custom batch size and verbose output
            bin/ots consolidate-redis-models --run --batch-size=50 --verbose

        USAGE
        return true
      end
      false
    end
  end
end

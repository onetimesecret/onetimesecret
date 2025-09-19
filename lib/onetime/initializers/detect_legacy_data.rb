# lib/onetime/initializers/detect_legacy_data.rb

module Onetime
  module Initializers

    # Detects legacy data distribution across multiple Redis databases
    # and warns about potential data loss when upgrading to db 0 defaults
    def detect_legacy_data
      return {} if skip_legacy_data_check?

      OT.ld "[detect_legacy_data] Scanning for legacy data across Redis databases..."

      legacy_locations = {}

      # Known legacy database mappings (from removed DATABASE_IDS constant)
      legacy_mappings = {
        'session' => [1],
        'splittest' => [1],
        'custom_domain' => [6],
        'customer' => [6],
        'subdomain' => [6],
        'metadata' => [7],
        'email_receipt' => [8],
        'secret' => [8],
        'feedback' => [11],
        'exception_info' => [12]
      }

      # Get current database configuration
      current_dbs = OT.conf.dig('redis', 'dbs') || {}

      # Scan databases 1-15 for legacy data (skip 0 as that's the target)
      (1..15).each do |db_num|
        next if scan_database_for_legacy_data(db_num, legacy_mappings, current_dbs, legacy_locations).zero?

        # If we found data, continue scanning to get complete picture
      end

      OT.ld "[detect_legacy_data] Scan complete. Found #{legacy_locations.size} model types with legacy data."
      legacy_locations
    rescue => ex
      OT.le "[detect_legacy_data] Error during legacy data detection: #{ex.message}"
      OT.ld ex.backtrace.join("\n")

      # Return empty hash on error to allow startup to continue
      # but log the issue for troubleshooting
      {}
    end

    # Scans a specific database for legacy data patterns
    # Returns count of model types found in this database
    def scan_database_for_legacy_data(db_num, legacy_mappings, current_dbs, legacy_locations)
      models_found = 0

      begin
        client = Familia.dbclient(db_num)

        # Quick connectivity check
        client.ping

        legacy_mappings.each do |model_name, expected_dbs|
          # Skip if this model is configured to be in this database
          current_db = current_dbs[model_name] || 0
          next if db_num == current_db

          # Check for model-specific key patterns
          key_pattern = "#{model_name}:*"
          keys = scan_for_model_keys(client, key_pattern)

          next if keys.empty?

          models_found += 1

          # Found data in unexpected location
          legacy_locations[model_name] ||= []
          legacy_locations[model_name] << {
            database: db_num,
            key_count: keys.length,
            sample_keys: keys.first(3),
            expected_database: current_db,
            was_legacy_default: expected_dbs.include?(db_num)
          }

          OT.ld "[detect_legacy_data] Found #{keys.length} #{model_name} keys in DB #{db_num} (expected DB #{current_db})"
        end

      rescue Redis::CannotConnectError, Redis::TimeoutError => ex
        OT.ld "[detect_legacy_data] Cannot connect to DB #{db_num}: #{ex.message}"
      rescue => ex
        OT.le "[detect_legacy_data] Error scanning DB #{db_num}: #{ex.message}"
      end

      models_found
    end

    # Scans for keys matching a specific pattern using Redis SCAN
    def scan_for_model_keys(client, pattern)
      keys = []
      cursor = "0"

      loop do
        result = client.scan(cursor, match: pattern, count: 100)
        cursor = result[0]
        keys.concat(result[1])

        # Stop after finding some keys (we just need to know data exists)
        break if !keys.empty? || cursor == "0"

        # Safety valve: don't scan forever
        break if keys.length > 1000
      end

      keys
    end

    # Displays warning about legacy data and provides actionable options
    def warn_about_legacy_data(legacy_locations)
      return if legacy_locations.empty?

      puts "\n" + "=" * 80
      puts "⚠️  WARNING: Legacy data detected in unexpected Redis databases!"
      puts "=" * 80

      puts "\nThis installation appears to have data distributed across multiple"
      puts "Redis logical databases, but your current configuration defaults"
      puts "everything to database 0. This can cause SILENT DATA LOSS where"
      puts "existing data becomes inaccessible after upgrade."

      puts "\n📊 LEGACY DATA FOUND:"

      legacy_locations.each do |model, locations|
        current_db = locations.first[:expected_database]
        puts "\n  #{model.capitalize} model (configured for DB #{current_db}):"

        locations.each do |location|
          legacy_note = location[:was_legacy_default] ? " [was legacy default]" : ""
          puts "    🔍 Found #{location[:key_count]} records in database #{location[:database]}#{legacy_note}"
          puts "       Sample keys: #{location[:sample_keys].join(', ')}" if location[:sample_keys].any?
        end
      end

      puts "\n🔧 RESOLUTION OPTIONS:"
      puts "\n  1. UPDATE CONFIGURATION to preserve current data distribution:"
      puts "     Add these environment variables to match your existing data:"

      legacy_locations.each do |model, locations|
        locations.each do |location|
          env_var = "REDIS_DBS_#{model.upcase}"
          puts "       export #{env_var}=#{location[:database]}"
        end
      end

      puts "\n  2. MIGRATE DATA to database 0 (recommended):"
      puts "     Run: bin/ots migrate-redis-data              # Preview changes (dry-run mode)"
      puts "     Then: bin/ots migrate-redis-data --run       # Perform migration"

      puts "\n  3. BYPASS CHECK and acknowledge potential data loss:"
      puts "     export SKIP_LEGACY_DATA_CHECK=true"
      puts "     export ACKNOWLEDGE_DATA_LOSS=true"
      puts "     ⚠️  WARNING: Data in non-zero databases will be INACCESSIBLE"

      puts "\n" + "=" * 80
      puts "Startup halted to prevent silent data loss."
      puts "Choose one of the options above and restart the application."
      puts "=" * 80 + "\n"

      exit 1 unless acknowledge_data_loss?
    end

    private

    # Check if legacy data detection should be skipped
    def skip_legacy_data_check?
      ENV['SKIP_LEGACY_DATA_CHECK'] == 'true'
    end

    # Check if user has acknowledged potential data loss
    def acknowledge_data_loss?
      ENV['ACKNOWLEDGE_DATA_LOSS'] == 'true'
    end

  end
end

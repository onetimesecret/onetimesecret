# lib/onetime/initializers/detect_legacy_data.rb

module Onetime
  module Initializers

    # Detects legacy data distribution across multiple Redis databases
    # and warns about potential data loss when upgrading to db 0 defaults
    def detect_legacy_data
      return { legacy_locations: {}, needs_auto_config: false } if skip_legacy_data_check?

      OT.ld "[detect_legacy_data] Scanning for existing data distribution..."

      legacy_locations = {}

      # Known legacy database mappings (from removed DATABASE_IDS constant)
      legacy_mappings = {
        'session' => [1],
        'customer' => [6],
        'customdomain' => [6],
        'metadata' => [7],
        'secret' => [8],
        'feedback' => [11],
      }

      # Get current database configuration
      current_dbs = OT.conf.dig('redis', 'dbs') || {}

      # Scan databases 1-15 for legacy data (skip 0 as that's the target)
      # Short-circuit when all models with legacy mappings are found
      target_models = legacy_mappings.keys
      models_found_count = 0

      legacy_counts = (1..15).map do |db_num|
        # Short-circuit if we've found all possible models
        break if legacy_locations.keys.size == target_models.size

        found_count = scan_database_for_legacy_data(db_num, legacy_mappings, current_dbs, legacy_locations)
        models_found_count += found_count

        OT.ld "[detect_legacy_data] Database #{db_num}: #{found_count} legacy records found"
        found_count
      end.compact

      # Determine if auto-configuration is needed
      needs_auto_config = legacy_locations.any? && using_default_database_config?(current_dbs, legacy_locations)

      total_model_types = models_found_count
      OT.ld <<~SCAN_COMPLETE_MESSAGE
        [detect_legacy_data] Scan complete.
        Found #{legacy_locations.size} model types with existing data across #{legacy_counts.size} databases.
        [detect_legacy_data] Total model instances found: #{total_model_types}
        [detect_legacy_data] Application will continue with current configuration.
      SCAN_COMPLETE_MESSAGE

      { legacy_locations: legacy_locations, needs_auto_config: needs_auto_config }

    rescue RuntimeError => ex
      OT.le "[detect_legacy_data] Error during legacy data detection: #{ex.message}"
      OT.ld ex.backtrace.join("\n")

      # Even though we want the update to v0.23 to be easy and not require
      # manual intervention, we still need to handle an error here gracefully.
      # The only responsible action here is to stop and suggest a remediation.
      OT.le <<~REMEDIATION_MESSAGE

        [detect_legacy_data] Cannot determine if existing data is present in legacy databases.
        To protect against potential data loss, startup is halted.

        RESOLUTION OPTIONS:
        1. Review the error details above and address the underlying issue
        2. Set explicit database configuration (see migration guide)
        3. Use SKIP_LEGACY_DATA_CHECK=true if you're certain no data exists

        See the Redis Data Migration Guide for detailed instructions.
        Contact support@onetimesecret.com if you need assistance.

      REMEDIATION_MESSAGE

      # NOTE: We must halt startup here to prevent potential data loss. When an
      # exception prevents us from detecting existing data in legacy databases,
      # we cannot safely determine if auto-configuration is appropriate. For existing
      # installations, auto-configuring to legacy databases preserves data access.
      # However, for new installations, this would perpetuate the old multi-database
      # configuration we're trying to migrate away from. Since we cannot distinguish
      # between these scenarios, the safest approach is to require manual
      # intervention via explicit configuration or environment flags.
      raise ex
    end

    # Determines if the current database configuration is using all defaults (database 0)
    # which means auto-configuration is needed to preserve access to legacy data
    def using_default_database_config?(current_dbs, legacy_locations)
      # If there's no explicit configuration at all, auto-configure everything
      return true if current_dbs.nil? || current_dbs.empty?

      # Check each model with legacy data to see if any need auto-configuration
      # A model needs auto-config if it has legacy data but is configured to use DB 0 (default)
      legacy_locations.keys.any? do |model|
        configured_db = current_dbs[model] || 0
        configured_db == 0  # Model with legacy data is using default DB 0
      end
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
          # Skip if this model already has legacy data detected in another database
          if legacy_locations.key?(model_name)
            OT.ld "[scan_database_for_legacy_data] Skipping #{model_name} (already detected in another database)"
            next
          end

          # Skip if this model is configured to be in this database
          # BUT for migration purposes, we want to find ALL data not in DB 0
          if migration_mode?
            # In migration mode, target database is always 0
            current_db = 0
          else
            current_db = current_dbs[model_name] || 0
            if db_num == current_db
              OT.ld "[scan_database_for_legacy_data] Skipping #{model_name} (already configured in this database)"
              next
            end
          end

          # Check for model-specific key patterns
          key_pattern = "#{model_name}:*"
          keys = scan_for_model_keys(client, key_pattern)

          if keys.empty?
            OT.ld "[scan_database_for_legacy_data] 0 #{model_name} keys found in DB #{db_num}"
            next
          end

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
      max_iterations = 10  # Limit scan iterations to prevent excessive startup time
      iterations = 0

      OT.ld "[scan_for_model_keys] Scanning for '#{pattern}' with #{client.inspect}"

      loop do
        result = client.scan(cursor, match: pattern, count: 100)
        cursor = result[0]
        keys.concat(result[1])
        iterations += 1

        # Stop after finding some keys (we just need to know data exists)
        if !keys.empty?
          OT.ld "[scan_for_model_keys] Found keys: #{keys}"
          break
        end

        # Stop if we've completed the scan
        if cursor == "0"
          OT.ld "[scan_for_model_keys] Completed scan #{result}"
          break
        end

        # Safety valve: don't scan forever
        if iterations >= max_iterations
          OT.ld "[scan_for_model_keys] Reached maximum iterations"
          break
        end
      end

      OT.ld "[scan_for_model_keys] Found keys: #{keys} with #{iterations} iterations"
      keys
    end

    # Displays warning about legacy data and provides actionable options
    def warn_about_legacy_data(detection_result)
      legacy_locations = detection_result[:legacy_locations] || detection_result  # Support old and new format
      needs_auto_config = detection_result[:needs_auto_config] || false

      return if legacy_locations.empty?

      if needs_auto_config
        # Auto-configure for compatibility
        puts "\nLEGACY DATA DETECTED - Auto-configuring for compatibility"
        puts "=" * 60

        puts "\nFound existing data in legacy databases:"
        legacy_locations.each do |model, locations|
          locations.each do |location|
            puts "  • #{location[:key_count]} #{model} records in database #{location[:database]}"
          end
        end

        # Apply auto-configuration
        apply_auto_configuration(legacy_locations)
        puts <<~AUTO_CONFIG_MESSAGE

        Auto-configured database mappings to preserve data access
           Your data remains accessible using legacy database locations

        To migrate to database 0 (recommended before v1.0):
           Run: bin/ots migrate-redis-data --run

        For permanent configuration options:
           See: docs/redis-migration.md
        AUTO_CONFIG_MESSAGE

        puts "\n" + "=" * 60 + "\n"
      else
        # Standard informational message for explicitly configured systems
        puts <<~LEGACY_DATA_MESSAGE

        LEGACY DATA DETECTED - No action required
        #{'=' * 50}

        Found existing data in legacy databases:
        LEGACY_DATA_MESSAGE

        legacy_locations.each do |model, locations|
          locations.each do |location|
            legacy_note = location[:was_legacy_default] ? " [was legacy default]" : ""
            puts "  • #{location[:key_count]} #{model} records in database #{location[:database]}#{legacy_note}"
          end
        end

        puts <<~EXISTING_CONFIG_MESSAGE

        ✅ Continuing with existing configuration
        Consider migrating to database 0 before v1.0 (see migration guide)

        Migration options available:
          1. No action needed - current setup continues working
          2. Migrate when convenient: bin/ots migrate-redis-data --run
          3. See docs/redis-migration.md for detailed guidance

        EXISTING_CONFIG_MESSAGE

        puts "=" * 50 + "\n"
      end

      # Only exit for fresh start scenarios where user wants to acknowledge data loss
      if ENV['ACKNOWLEDGE_DATA_LOSS'] == 'true' && ENV['SKIP_LEGACY_DATA_CHECK'] == 'true'
        puts "⚠️ Fresh start mode enabled - legacy data will be inaccessible"
        puts "Continuing with database 0 configuration..."
      end
    end

    # Applies auto-configuration by updating OT.conf to match legacy data locations
    def apply_auto_configuration(legacy_locations)
      # Get the current configuration (make sure it's mutable)
      current_conf = OT.conf

      # Ensure redis.dbs section exists
      current_conf['redis'] ||= {}
      current_conf['redis']['dbs'] ||= {}

      OT.ld "[apply_auto_configuration] Applying auto-configuration for legacy data compatibility"

      # Configure each model to use its detected legacy database
      legacy_locations.each do |model, locations|
        # Use the first (and typically only) location for each model
        primary_location = locations.first
        legacy_db = primary_location[:database]

        # Update configuration to use the legacy database
        current_conf['redis']['dbs'][model] = legacy_db

        OT.ld "[apply_auto_configuration] Configured #{model} to use database #{legacy_db}"
      end

      OT.ld "[apply_auto_configuration] Auto-configuration complete"
    end

    private

    # Check if legacy data detection should be skipped
    def skip_legacy_data_check?
      # Skip if explicitly disabled via environment variable
      return true if ENV['SKIP_LEGACY_DATA_CHECK'] == 'true'

      # Skip during test mode to avoid Redis mock conflicts
      return true if defined?(OT) && OT.mode?(:test)

      # Skip during testing environment (covers CI scenarios)
      return true if defined?(OT) && OT.env == 'testing'

      false
    end

    # Check if user has acknowledged potential data loss
    def acknowledge_data_loss?
      ENV['ACKNOWLEDGE_DATA_LOSS'] == 'true'
    end

    # Check if we're in migration mode - find ALL data not in DB 0
    def migration_mode?
      ENV['MIGRATION_MODE'] == 'true'
    end

  end
end

# lib/onetime/migration/model_migration.rb

require_relative 'base_migration'

module Onetime
  # Base class for migrations that operate on Familia::Horreum models
  #
  # Provides standardized patterns for:
  # - Redis SCAN-based iteration over model records
  # - Progress tracking and reporting
  # - Error handling and recovery
  # - Dry-run/actual-run modes
  #
  # Usage:
  #   class MyModelMigration < ModelMigration
  #     def prepare
  #       @model_class = V2::Customer
  #       @batch_size = 1000  # optional, defaults to 1000
  #     end
  #
  #     def process_record(obj)
  #       # Implement record processing logic
  #       # Use track_stat() to count operations
  #       # Wrap updates in for_realsies_this_time? block
  #     end
  #   end
  class ModelMigration < BaseMigration
    attr_reader :model_class, :batch_size, :total_records, :total_scanned,
      :records_needing_update, :records_updated, :error_count, :interactive

    def initialize
      super
      @batch_size             = 1000
      @total_scanned          = 0
      @records_needing_update = 0
      @records_updated        = 0
      @error_count            = 0
    end

    # Override to set @model_class and optionally @batch_size
    def prepare
      raise NotImplementedError, "#{self.class} must set @model_class in #prepare"
    end

    # Process a single record. Must be implemented by subclasses.
    # @param obj [Familia::Horreum] The model instance to process
    def process_record(obj)
      raise NotImplementedError, "#{self.class} must implement #process_record"
    end

    # Main migration implementation - handles the Redis SCAN loop
    def migrate # rubocop:disable Naming/PredicateMethod
      validate_model_class!

      # Set `@interactive = true` in the implementing migration class
      # for an interactive debug session on a per-record basis.
      require 'pry-byebug' if interactive

      run_mode_banner

      info("[#{self.class.name.split('::').last}] Starting #{model_class.name} migration")
      info("Processing up to #{total_records} records")
      info('Will show progress every 100 records and log each update')

      scan_and_process_records

      print_migration_summary

      @error_count == 0
    end

    # Default implementation - always returns true
    # Always return true to allow re-running for error recovery
    # The migration is idempotent - it won't overwrite existing values
    # Override if you need conditional migration logic
    def migration_needed?
      info("[#{self.class.name.split('::').last}] Checking if migration is needed...")
      true
    end

    private

    def validate_model_class!
      unless defined?(@model_class) && @model_class
        raise 'Model class not set. Define @model_class in your #prepare method'
      end

      unless @model_class.respond_to?(:redis) && @model_class.respond_to?(:prefix)
        raise 'Model class must be a Familia::Horreum subclass'
      end

      @total_records = @model_class.values.size
      @redis_client  = @model_class.redis
      @scan_pattern  = "#{@model_class.prefix}:*:object"

      info("Model class: #{@model_class.name}")
      info("Redis connection: #{@redis_client.connection[:id]}")
      info("Scan pattern: #{@scan_pattern}")
      info("Total records: #{@total_records}")
      info("Batch size: #{@batch_size}")

      # Test Redis connection
      begin
        @redis_client.ping
        debug('Redis connection verified')
      rescue StandardError => ex
        error("Cannot connect to Redis: #{ex.message}")
        raise ex
      end
    end

    def scan_and_process_records
      cursor = '0'

      loop do
        cursor, keys    = @redis_client.scan(cursor, match: @scan_pattern, count: @batch_size)
        @total_scanned += keys.size

        # Always show progress for first few batches, then every 100 records
        if @total_scanned <= 500 || @total_scanned % 100 == 0
          progress(@total_scanned, @total_records, "Scanning #{model_class.name.split('::').last} records")
        end

        # Show batch info for debugging
        info("Processing batch of #{keys.size} keys...") unless keys.empty?

        keys.each do |key|
          process_single_record(key)
        end

        break if cursor == '0'
      end
    end

    def process_single_record(key)
        # Load the model instance
        obj = model_class.find_by_key(key)

        # Track if this record needed processing
        records_updated_before = @records_updated
        would_update_before    = @stats[:records_would_update] || 0

        # Call the subclass implementation
        process_record(obj)

        # Check if record was processed (either updated or would be updated in dry-run)
        records_actually_updated = @records_updated > records_updated_before
        records_would_be_updated = (@stats[:records_would_update] || 0) > would_update_before

        if records_actually_updated || records_would_be_updated
          @records_needing_update      += 1
          # Reset the would-update counter after using it
          @stats[:records_would_update] = would_update_before if records_would_be_updated
        end
    rescue StandardError => ex
        @error_count += 1
        error("Error processing #{key}: #{ex.message}")
        debug(%(Stack trace: #{ex.backtrace.first(5).join("\n")}))

        binding.pry if interactive # rubocop:disable Lint/Debugger

        track_stat(:errors)
    end

    def print_migration_summary
      print_summary do
        info("Total #{model_class.name.split('::').last} records scanned: #{@total_scanned}")
        info("Records needing update: #{@records_needing_update}")
        info("Records #{actual_run? ? 'updated' : 'that would be updated'}: #{@records_updated}")
        info("Errors encountered: #{@error_count}")

        # Print any custom stats
        if @stats.any?
          info('')
          info('Additional statistics:')
          @stats.each do |key, value|
            next if [:errors, :records_updated, :records_would_update].include?(key)

            info("  #{key}: #{value}")
          end
        end

        if @error_count > 0
          info('')
          info('Check logs for error details')
        end

        if dry_run? && @records_needing_update > 0
          info('')
          info('Run with --run to apply these updates')
        end
      end
    end

    # Override to track record updates automatically
    def track_stat(key, increment = 1)
      super
      @records_updated += increment if key == :records_updated
    end

    # Helper method for migrations to indicate a record would be updated in dry-run
    def would_update_record
      track_stat(:records_would_update) if dry_run?
      track_stat(:records_updated) if actual_run?
    end

    # Helper method to get record data from Redis
    # Useful when you need raw hash access
    def get_record_data(key)
      @redis_client.hgetall(key)
    end

    # Helper to update multiple fields atomically
    def update_record_fields(key, fields)
      return if fields.empty?

      @redis_client.hmset(key, *fields.to_a.flatten)
    end
  end
end

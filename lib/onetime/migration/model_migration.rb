# lib/onetime/migration/model_migration.rb

require_relative 'base_migration'

module Onetime
  # Base class for individual record migrations on Familia::Horreum models
  #
  # Provides Redis SCAN-based iteration with progress tracking, error handling,
  # and dry-run/actual-run modes for processing records one at a time.
  #
  # ## When to Use ModelMigration vs PipelineMigration
  #
  # Use **ModelMigration** when:
  # - Complex logic is needed for each record
  # - Error handling per record is important
  # - Records need individual validation
  # - Updates vary significantly between records
  #
  # Use **PipelineMigration** when:
  # - Simple bulk updates across many records
  # - Performance is critical for large datasets
  # - All records get similar field updates
  # - Redis pipelining can be utilized effectively
  #
  # ## Subclassing Requirements
  #
  # Subclasses must implement:
  # - {#prepare} - Set @model_class and optionally @batch_size
  # - {#process_record} - Handle individual record processing
  #
  # Subclasses may override:
  # - {#migration_needed?} - Default returns true (always migrate)
  # - {#load_from_key} - Custom object loading from database keys
  #
  # ## Usage Example
  #
  #   class CustomerEmailMigration < ModelMigration
  #     def prepare
  #       @model_class = V2::Customer
  #       @batch_size = 1000  # optional, defaults to 1000
  #     end
  #
  #     def process_record(obj, key)
  #       return unless obj.email.blank?
  #
  #       for_realsies_this_time? do
  #         obj.email = "#{obj.custid}@example.com"
  #         obj.save
  #       end
  #       track_stat(:emails_updated)
  #     end
  #   end
  #
  # ## Development Rule
  #
  # **IMPORTANT**: Deploy schema changes and logic changes separately.
  # This prevents new model logic from breaking migration logic and
  # reduces debugging complexity.
  #
  # @abstract Subclass and implement {#prepare} and {#process_record}
  # @see PipelineMigration For bulk processing with Redis pipelining
  class ModelMigration < BaseMigration
    # Model class being migrated
    # @return [Class] Familia::Horreum subclass
    attr_reader :model_class

    # Number of keys to scan per Redis SCAN operation
    # @return [Integer] batch size for scanning
    attr_reader :batch_size

    # Total number of indexed records in the model
    # @return [Integer] count from model_class.values
    attr_reader :total_records

    # Number of keys found by Redis SCAN
    # @return [Integer] actual keys discovered
    attr_reader :total_scanned

    # Records that passed through process_record
    # @return [Integer] count of records needing updates
    attr_reader :records_needing_update

    # Records successfully updated
    # @return [Integer] count of records modified
    attr_reader :records_updated

    # Number of processing errors encountered
    # @return [Integer] error count
    attr_reader :error_count

    # Interactive debugging mode flag
    # @return [Boolean] whether to drop into pry on errors
    attr_reader :interactive

    # Redis SCAN pattern for finding records
    # @return [String] pattern like "customer:*:object"
    attr_reader :scan_pattern

    # Redis client instance for the model
    # @return [Redis] model's Redis connection
    attr_reader :dbclient

    def initialize
      super
      reset_counters
      set_defaults
    end

    # Main migration entry point
    #
    # Validates configuration, displays run mode information,
    # executes the SCAN-based record processing, and displays
    # a comprehensive summary.
    #
    # @return [Boolean] true if no errors occurred
    def migrate
      validate_model_class!

      # Set `@interactive = true` in the implementing migration class
      # for an interactive debug session on a per-record basis.
      require 'pry-byebug' if interactive

      print_database_details
      run_mode_banner

      info("[#{self.class.name.split('::').last}] Starting #{model_class.name} migration")
      info("Processing up to #{total_records} records")
      info('Will show progress every 100 records and log each update')

      scan_and_process_records
      print_database_details
      print_migration_summary

      @error_count == 0
    end

    # Default migration check - always returns true
    #
    # Always return true to allow re-running for error recovery.
    # The migration should be idempotent - it won't overwrite existing values.
    # Override if you need conditional migration logic.
    #
    # @return [Boolean] true to proceed with migration
    def migration_needed?
      debug("[#{self.class.name.split('::').last}] Checking if migration is needed...")
      true
    end

    # Load Familia::Horreum object instance from database key
    #
    # Override this method to customize loading behavior. For example,
    # with a custom @scan_pattern, the migration might loop through
    # relation keys of a horreum model (e.g. customer:ID:custom_domain).
    #
    # Typically migrations iterate over objects themselves, but this
    # won't work if there are dangling "orphan" keys without corresponding
    # objects. Override this method to handle such cases.
    #
    # @param key [String] database key to load from
    # @return [Familia::Horreum, Familia::RedisType] loaded object instance
    def load_from_key(key)
      model_class.find_by_key(key)
    end

    protected

    # Set @model_class and optionally @batch_size
    #
    # **Required for subclasses** - must set @model_class to a
    # Familia::Horreum subclass. Can optionally set @batch_size
    # to override the default of 1000.
    #
    # @abstract Subclasses must implement this method
    # @return [void]
    # @raise [NotImplementedError] if not implemented
    def prepare
      raise NotImplementedError, "#{self.class} must set @model_class in #prepare"
    end

    # Process a single record
    #
    # **Required for subclasses** - implement the core logic for
    # processing each record. Use {#track_stat} to count operations
    # and {#for_realsies_this_time?} to wrap actual changes.
    #
    # @abstract Subclasses must implement this method
    # @param obj [Familia::Horreum, Familia::DataType] The familia class instance to process
    # @param key [String] The dbkey of the record
    # @return [void]
    # @raise [NotImplementedError] if not implemented
    def process_record(obj, key)
      raise NotImplementedError, "#{self.class} must implement #process_record"
    end

    # Track statistics and auto-increment records_updated counter
    #
    # Automatically increments @records_updated when statname is :records_updated.
    # Use this to maintain consistent counting across migrations.
    #
    # @param statname [Symbol] The name of the statistic to track
    # @param increment [Integer] The amount to increment by
    # @return [void]
    def track_stat(statname, increment = 1)
      super
      @records_updated += increment if statname == :records_updated
    end

    # Track stat and log decision reason in one call
    #
    # Convenience method for logging migration decisions with consistent
    # formatting and automatic statistic tracking.
    #
    # @param obj [Familia::Horreum] object being processed
    # @param decision [String] decision made (e.g., 'skipped', 'updated')
    # @param field [String] field name involved in decision
    # @return [nil]
    def track_stat_and_log_reason(obj, decision, field)
      track_stat(:decision)
      track_stat("#{decision}_#{field}")
      info("#{decision} objid=#{obj.objid} #{field}=#{obj.send(field)}")
      nil
    end

    private

    def reset_counters
      @total_scanned          = 0
      @records_needing_update = 0
      @records_updated        = 0
      @error_count            = 0
    end

    def set_defaults
      @batch_size   = 1000
      @model_class  = nil
      @scan_pattern = nil
      @interactive  = false
      @dbclient     = nil
    end

    def validate_model_class!
      raise 'Model class not set. Define @model_class in your #prepare method' unless @model_class
      raise 'Model class must be a Familia::Horreum subclass' unless familia_horreum_class?

      @total_records  = @model_class.values.size
      @dbclient     ||= @model_class.dbclient
      @scan_pattern ||= "#{@model_class.prefix}:*:object"
      nil
    end

    def familia_horreum_class?
      @model_class.respond_to?(:redis) && @model_class.respond_to?(:prefix)
    end

    def scan_and_process_records
      cursor = '0'

      loop do
        cursor, keys    = @dbclient.scan(cursor, match: @scan_pattern, count: @batch_size)
        @total_scanned += keys.size

        show_progress if should_show_progress?
        info("Processing batch of #{keys.size} keys...") unless keys.empty?

        keys.each { |key| process_single_record(key) }
        break if cursor == '0'
      end
    end

    def should_show_progress?
      @total_scanned <= 500 || @total_scanned % 100 == 0
    end

    def show_progress
      progress(@total_scanned, @total_records, "Scanning #{model_class.name.split('::').last} records")
    end

    def process_single_record(key)
      obj = load_from_key(key)

      # Every record that gets processed is considered as needing update. The
      # idempotent operations in process_record determine whether changes are
      # actually made.
      @records_needing_update += 1

      # Call the subclass implementation
      process_record(obj, key)
    rescue StandardError => ex
      handle_record_error(key, ex)
    end

    def handle_record_error(key, ex)
      @error_count += 1
      error("Error processing #{key}: #{ex.message}")
      debug("Stack trace: #{ex.backtrace.first(10).join('; ')}")
      track_stat(:errors)

      binding.pry if interactive # rubocop:disable Lint/Debugger
    end

    def print_migration_summary
      print_summary do
        info("Redis SCAN found: #{@total_scanned} #{model_class} records")
        info("Passed migration filter: #{@records_needing_update} records")
        info("#{actual_run? ? 'Processed' : 'Would be processed'}: #{@records_updated} records")
        info("Errors: #{@error_count}")

        print_custom_stats
        print_error_guidance
        print_dry_run_guidance
      end
    end

    def print_custom_stats
      return unless @stats.any?

      info('')
      info('Additional statistics:')
      @stats.each do |key, value|
        next if [:errors, :records_updated].include?(key)

        info("  #{key}: #{value}")
      end
    end

    def print_error_guidance
      info('', 'Check logs for error details') if @error_count > 0
    end

    def print_dry_run_guidance
      return unless dry_run? && @records_needing_update > 0

      info ''
      info 'Run with --run to apply these updates'
    end

    def print_database_details
      print_summary('Redis Details') do
        info("Model class: #{@model_class.name}")
        info("Redis connection: #{@dbclient.connection[:id]}")
        info("Scan pattern: #{@scan_pattern}")
        info("Indexed records: #{@total_records} (#{@model_class.name}.values)")
        info("Batch size: #{@batch_size}")
        verify_database_connection
      end
    end

    def verify_database_connection
      @dbclient.ping
      debug('Redis connection: verified')
    rescue StandardError => ex
      error("Cannot connect to the database: #{ex.message}")
      raise ex
    end
  end
end

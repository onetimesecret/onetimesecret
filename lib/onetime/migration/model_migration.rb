# lib/onetime/migration/model_migration.rb

require_relative 'base_migration'

module Onetime
  # Base class for individual record migrations on Familia::Horreum models
  #
  # Provides Redis SCAN-based iteration with progress tracking, error handling,
  # and dry-run/actual-run modes.
  #
  # Usage:
  #   class MyModelMigration < ModelMigration
  #     def prepare
  #       @model_class = V2::Customer
  #       @batch_size = 1000  # optional, defaults to 1000
  #     end
  #
  #     def process_record(obj, key)
  #       # Implement record processing logic
  #       # Use track_stat() to count operations
  #       # Wrap updates in for_realsies_this_time? block
  #     end
  #   end
  #
  # RULE: Deploy schema changes and logic changes separately. This prevents
  # new model logic from breaking migration logic. It can also be confusing.
  #
  class ModelMigration < BaseMigration
    attr_reader :model_class, :batch_size, :total_records, :total_scanned,
      :records_needing_update, :records_updated, :error_count,
      :interactive, :scan_pattern, :redis_client

    def initialize
      super
      reset_counters
      set_defaults
    end

    # Main migration entry point
    def migrate
      validate_model_class!

      # Set `@interactive = true` in the implementing migration class
      # for an interactive debug session on a per-record basis.
      require 'pry-byebug' if interactive

      print_redis_details
      run_mode_banner

      info("[#{self.class.name.split('::').last}] Starting #{model_class.name} migration")
      info("Processing up to #{total_records} records")
      info('Will show progress every 100 records and log each update')

      scan_and_process_records
      print_redis_details
      print_migration_summary

      @error_count == 0
    end

    # Default: always migrate (override for conditional logic)
    #
    # Always return true to allow re-running for error recovery
    # The migration is idempotent - it won't overwrite existing values
    # Override if you need conditional migration logic
    def migration_needed?
      debug("[#{self.class.name.split('::').last}] Checking if migration is needed...")
      true
    end

    # Loads a Familia::Horeum object instance from a redis key
    #
    # NOTE: Override this method to customize the loading behavior. For example,
    # with a custom @scan_pattern, the migration might be looping through
    # the relation keys of a horreum model (e.g. a customer that has a custom
    # domain configured will have its customer:ID:object key as well as a
    # customer:ID:custom_domain key).
    #
    # Typically a migration will iterate over the objects themselves, but that
    # won't work if there are dangling "orphan" keys that don't have a
    # corresponding object. To address that, provide a load_from_key method
    # in the migration to load the customer:ID:custom_domain sorted set. Then
    # the process_record method will receive an instance of Familia::SortedSet.
    #
    def load_from_key(key)
      model_class.find_by_key(key)
    end

    protected

    # Set @model_class and optionally @batch_size
    def prepare
      raise NotImplementedError, "#{self.class} must set @model_class in #prepare"
    end

    # Process a single record (implement in subclass)
    # @param obj [Familia::Horreum, Familia::RedisType] The familia class
    # instance to process
    # @param key [String] The redis key of the record
    def process_record(obj, key)
      raise NotImplementedError, "#{self.class} must implement #process_record"
    end

    # Call this to track a stat or count record updates automatically
    #
    # @param statname [Symbol] The name of the statistic to track (can be anything)
    # @param increment [Integer] The amount to increment the statistic by
    def track_stat(statname, increment = 1)
      super
      @records_updated += increment if statname == :records_updated
    end

    # A convenience method to track a stat and log a reason for the decision
    # in one line.
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
      @redis_client = nil
    end

    def validate_model_class!
      raise 'Model class not set. Define @model_class in your #prepare method' unless @model_class
      raise 'Model class must be a Familia::Horreum subclass' unless familia_horreum_class?

      @total_records  = @model_class.values.size
      @redis_client ||= @model_class.redis
      @scan_pattern ||= "#{@model_class.prefix}:*:object"
      nil
    end

    def familia_horreum_class?
      @model_class.respond_to?(:redis) && @model_class.respond_to?(:prefix)
    end

    def scan_and_process_records
      cursor = '0'

      loop do
        cursor, keys    = @redis_client.scan(cursor, match: @scan_pattern, count: @batch_size)
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
        info("Total #{model_class.name.split('::').last} records scanned: #{@total_scanned} (actual)")
        info("Records that met basic criteria: #{@records_needing_update}")
        info("Records #{actual_run? ? 'updated' : 'that would be updated on actual run'}: #{@records_updated}")
        info("Errors encountered: #{@error_count}")

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

    def print_redis_details
      print_summary('Redis Details') do
        info("Model class: #{@model_class.name}")
        info("Redis connection: #{@redis_client.connection[:id]}")
        info("Scan pattern: #{@scan_pattern}")
        info("Total records (#{@model_class.name}.values.size): #{@total_records} (expected)")
        info("Batch size: #{@batch_size}")
        verify_redis_connection
      end
    end

    def verify_redis_connection
      @redis_client.ping
      debug('Redis connection verified')
    rescue StandardError => ex
      error("Cannot connect to Redis: #{ex.message}")
      raise ex
    end
  end
end

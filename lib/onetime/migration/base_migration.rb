# lib/onetime/migration/base_migration.rb

require 'onetime'

unless defined?(APPS_ROOT)
  APPS_ROOT = File.join(OT::HOME, 'apps').freeze
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))
end

require 'onetime/models'

module Onetime
  # Base class for OneTimeSecret data migrations providing common infrastructure
  # for idempotent data transformations and configuration updates.
  #
  # Unlike traditional database migrations, these migrations:
  # - Don't track execution state in a migrations table
  # - Use {#migration_needed?} to detect if changes are required
  # - Support both dry-run and actual execution modes
  # - Provide built-in statistics tracking and logging
  #
  # ## Subclassing Requirements
  #
  # Subclasses must implement these methods:
  # - {#migration_needed?} - Detect if migration should run
  # - {#migrate} - Perform the actual migration work
  #
  # Subclasses may override:
  # - {#prepare} - Initialize and validate migration parameters
  #
  # ## Usage Patterns
  #
  # For simple data migrations, extend BaseMigration directly:
  #
  #   class ConfigurationMigration < BaseMigration
  #     def migration_needed?
  #       !OT::Config.setting_exists?(:new_feature_flag)
  #     end
  #
  #     def migrate
  #       for_realsies_this_time? do
  #         OT::Config.set(:new_feature_flag, true)
  #       end
  #       track_stat(:settings_updated)
  #     end
  #   end
  #
  # For record-by-record processing, use {ModelMigration}.
  # For bulk updates with Redis pipelining, use {PipelineMigration}.
  #
  # ## CLI Usage
  #
  #   bin/ots migrate my_migration.rb           # Dry run (preview)
  #   bin/ots migrate --run my_migration.rb     # Actual execution
  #
  # @abstract Subclass and implement {#migration_needed?} and {#migrate}
  # @see ModelMigration For individual record processing
  # @see PipelineMigration For bulk record processing with pipelining
  class BaseMigration
    # CLI options passed to migration, typically { run: true/false }
    # @return [Hash] the options hash
    attr_accessor :options

    # Migration statistics for tracking operations performed
    # @return [Hash] auto-incrementing counters for named statistics
    attr_reader :stats

    # Initialize new migration instance with default state
    def initialize
      @options = {}
      @stats   = Hash.new(0)  # Auto-incrementing counter for tracking migration stats
    end

    # Main entry point for migration execution
    #
    # Orchestrates the full migration process including preparation,
    # conditional execution based on {#migration_needed?}, and cleanup.
    #
    # @param options [Hash] CLI options, typically { run: true/false }
    # @return [Boolean, nil] true if migration completed successfully, nil if not needed
    def self.run(options = {})
      migration         = new
      migration.options = options
      migration.prepare

      return migration.handle_migration_not_needed unless migration.migration_needed?

      migration.migrate
    end

    # Hook for subclass initialization and validation
    #
    # Override this method to:
    # - Set instance variables needed by the migration
    # - Validate prerequisites and configuration
    # - Initialize connections or external dependencies
    #
    # @return [void]
    def prepare
      debug('Preparing migration - default implementation')
    end

    # Perform actual migration work
    #
    # This is the core migration logic that subclasses must implement.
    # Use {#for_realsies_this_time?} to wrap actual changes and
    # {#track_stat} to record operations performed.
    #
    # @abstract Subclasses must implement this method
    # @return [Boolean] true if migration succeeded
    # @raise [NotImplementedError] if not implemented by subclass
    def migrate
      raise NotImplementedError, "#{self.class} must implement #migrate"
    end

    # Detect if migration needs to run
    #
    # This method should implement idempotency logic by checking
    # current system state and returning false if migration has
    # already been applied or is not needed.
    #
    # @abstract Subclasses must implement this method
    # @return [Boolean] true if migration should proceed
    # @raise [NotImplementedError] if not implemented by subclass
    def migration_needed?
      raise NotImplementedError, "#{self.class} must implement #migration_needed?"
    end

    # === Run Mode Control ===

    # Check if migration is running in dry-run mode
    # @return [Boolean] true if no changes should be made
    def dry_run?
      !options[:run]
    end

    # Check if migration is running in actual execution mode
    # @return [Boolean] true if changes will be applied
    def actual_run?
      options[:run]
    end

    # Display run mode banner with appropriate warnings
    # @return [void]
    def run_mode_banner
      header("Running in #{dry_run? ? 'DRY RUN' : 'ACTUAL RUN'} mode")
      info(dry_run? ? 'No changes will be made' : 'Changes WILL be applied to the database')
      info(separator)
    end

    # Execute block only in actual run mode
    #
    # Use this to wrap code that makes actual changes to the system.
    # In dry-run mode, the block will not be executed.
    #
    # @yield Block to execute if in actual run mode
    # @return [Boolean] true if block was executed, false if skipped
    def for_realsies_this_time?
      return false unless actual_run?

      yield
      true
    end

    # Execute block only in dry run mode
    #
    # Use this for dry-run specific logging or validation.
    #
    # @yield Block to execute if in dry run mode
    # @return [Boolean] true if block was executed, false if skipped
    def dry_run_only?
      return false unless dry_run?

      yield
      true
    end

    # === Statistics Tracking ===

    # Increment named counter for migration statistics
    #
    # Use this to track operations, errors, skipped records, etc.
    # Statistics are automatically displayed in migration summaries.
    #
    # @param key [Symbol] stat name to increment
    # @param increment [Integer] amount to add (default 1)
    # @return [nil]
    def track_stat(key, increment = 1)
      @stats[key] += increment
      nil
    end

    # === Logging Interface ===

    # Print formatted header with separator lines
    # @param message [String] header text to display
    # @return [void]
    def header(message)
      info ''
      info separator
      info( message.upcase)
    end

    # Log informational message
    # @param args [Array] arguments passed to OT.li
    # @return [void]
    def info(*args)
      OT.li(*args)
    end

    def debug(*args)
      OT.ld(*args)
    end

    def warn(*args)
      OT.lw(*args)
    end

    def error(*args)
      OT.le(*args)
    end

    # Generate separator line for visual formatting
    # @return [String] dash separator line
    def separator
      '-' * 60
    end

    # Progress indicator for long operations
    #
    # Displays progress updates at specified intervals to avoid
    # overwhelming the log output during bulk operations.
    #
    # @param current [Integer] current item number
    # @param total [Integer] total items to process
    # @param message [String] operation description
    # @param step [Integer] progress reporting frequency (default 100)
    # @return [void]
    def progress(current, total, message = 'Processing', step = 100)
      return unless current % step == 0 || current == total

      OT.li "#{message} #{current}/#{total}..."
    end

    # Display migration summary with custom content block
    #
    # Automatically adjusts header based on run mode and yields
    # the current mode to the block for conditional content.
    #
    # @param title [String, nil] custom summary title
    # @yield [Symbol] :dry_run or :actual_run for conditional content
    # @return [void]
    def print_summary(title = nil)
      if dry_run?
        header(title || 'DRY RUN SUMMARY')
        yield(:dry_run) if block_given?
      else
        header(title || 'ACTUAL RUN SUMMARY')
        yield(:actual_run) if block_given?
      end
    end

    # Handle case where migration is not needed
    #
    # Called automatically when {#migration_needed?} returns false.
    # Provides standard messaging about migration state.
    #
    # @return [nil]
    def handle_migration_not_needed
      info('')
      info('Migration needed? false.')
      info('')
      info('This usually means that the migration has already been applied.')
      nil
    end

    protected

    # Access to database client (defaults to DB 6)
    #
    # Provides a database connection for migrations
    # that need to access data outside of Familia models.
    #
    # @return [Redis] configured Redis connection
    def dbclient
      @dbclient ||= Familia.dbclient(6)
    end

  end
end

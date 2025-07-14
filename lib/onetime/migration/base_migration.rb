# lib/onetime/migration.rb

require 'onetime'

unless defined?(APPS_ROOT)
  APPS_ROOT = File.join(OT::HOME, 'apps').freeze
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
  $LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))
end

require 'onetime/models'

module Onetime
  # Base class for OneTimeSecret data migrations
  #
  # Idempotent scripts that modify application data or configuration.
  # Unlike database migrations, these don't track execution state - instead
  # they detect if changes are needed via migration_needed?.
  #
  # Usage:
  #   class MyMigration < BaseMigration
  #     def migration_needed?
  #       # Return true if migration should run
  #     end
  #
  #     def migrate
  #       # Perform the actual migration work
  #     end
  #   end
  #
  # CLI: `bin/ots migrate [--run] my_migration.rb`
  class BaseMigration
    attr_accessor :options
    attr_reader :stats

    def initialize
      @options = {}
      @stats   = Hash.new(0)  # Auto-incrementing counter for tracking migration stats
    end

    # Main entry point - orchestrates full migration process
    # @param options [Hash] CLI options, typically { run: true/false }
    # @return [Boolean] true if migration completed successfully
    def self.run(options = {})
      migration         = new
      migration.options = options
      migration.prepare

      return migration.handle_migration_not_needed unless migration.migration_needed?

      migration.migrate
    end

    # Hook for subclass initialization and validation
    def prepare
      debug('Preparing migration - default implementation')
    end

    # Perform actual migration work (implement in subclass)
    # @return [Boolean] true if migration succeeded
    def migrate
      raise NotImplementedError, "#{self.class} must implement #migrate"
    end

    # Detect if migration needs to run (implement in subclass)
    # @return [Boolean] true if migration should proceed
    def migration_needed?
      raise NotImplementedError, "#{self.class} must implement #migration_needed?"
    end

    # === Run Mode Control ===

    def dry_run?
      !options[:run]
    end

    def actual_run?
      options[:run]
    end

    def run_mode_banner
      header("Running in #{dry_run? ? 'DRY RUN' : 'ACTUAL RUN'} mode")
      info(dry_run? ? 'No changes will be made' : 'Changes WILL be applied to the database')
      info(separator)
    end

    # Execute block only in actual run mode
    # @yield Block to execute if in actual run mode
    # @return [Boolean] true if block was executed
    def for_realsies_this_time?
      return false unless actual_run?

      yield
      true
    end

    # Execute block only in dry run mode
    def dry_run_only?
      return false unless dry_run?

      yield
      true
    end

    # === Statistics Tracking ===

    # Increment named counter for migration statistics
    # @param key [Symbol] stat name to increment
    # @param increment [Integer] amount to add (default 1)
    def track_stat(key, increment = 1)
      @stats[key] += increment
      nil
    end

    # === Logging Interface ===

    def header(message)
      info ''
      info separator
      info( message.upcase)
    end

    def info(*)
      OT.li(*)
    end

    def debug(*)
      OT.ld(*)
    end

    def warn(*)
      OT.lw(*)
    end

    def error(*)
      OT.le(*)
    end

    def separator
      '-' * 60
    end

    # Progress indicator for long operations
    # @param current [Integer] current item number
    # @param total [Integer] total items to process
    # @param message [String] operation description
    # @param step [Integer] progress reporting frequency
    def progress(current, total, message = 'Processing', step = 100)
      return unless current % step == 0 || current == total

      OT.li "#{message} #{current}/#{total}..."
    end

    # Display migration summary with custom content block
    def print_summary(title = nil)
      if dry_run?
        header(title || 'DRY RUN SUMMARY')
        yield(:dry_run) if block_given?
      else
        header(title || 'ACTUAL RUN SUMMARY')
        yield(:actual_run) if block_given?
      end
    end

    def handle_migration_not_needed
      info('')
      info('Migration needed? false.')
      info('')
      info('This usually means that the migration has already been applied.')
      nil
    end

    protected

    # Access to Redis database (defaults to DB 6)
    # @return [Redis] configured Redis connection
    def redis
      @redis ||= Familia.redis(6)
    end

  end
end

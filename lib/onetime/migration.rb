# lib/onetime/migration.rb

require 'onetime'

APPS_ROOT = File.join(OT::HOME, 'apps').freeze
$LOAD_PATH.unshift(File.join(APPS_ROOT, 'api'))
$LOAD_PATH.unshift(File.join(APPS_ROOT, 'web'))

require 'onetime/models'

module Onetime
  # Base class for OneTimeSecret data migrations
  #
  # Migrations are idempotent scripts that modify application data or configuration.
  # Unlike traditional database migrations, these don't track execution state -
  # instead they detect if changes are needed via migration_needed?.
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
  # Run via CLI: `bin/ots migrate [--run] my_migration.rb`
  class BaseMigration
    attr_accessor :options
    attr_reader :stats

    def initialize
      @options = {}
      @stats   = Hash.new(0)  # Auto-incrementing counter for tracking migration stats

      OT.boot! unless OT.ready?
    end

    # Main entry point - orchestrates the full migration process
    # @param options [Hash] CLI options, typically { run: true/false }
    # @return [Boolean] true if migration completed successfully
    def self.run(options = {})
      migration         = new
      migration.options = options
      migration.prepare

      is_needed = migration.migration_needed?
      migration.info ''
      migration.info("Migration needed? #{is_needed}.")
      unless is_needed
        migration.info ''
        migration.migration_not_needed_banner
        return false
      end

      migration.migrate
    end

    # Hook for subclasses to initialize instance variables and validate preconditions
    # Called before migration_needed? check
    def prepare
      debug('Preparing migration - default implementation')
    end

    # Perform the actual migration work
    # Must be implemented by subclasses
    # @return [Boolean] true if migration succeeded
    def migrate
      raise NotImplementedError, "#{self.class} must implement #migrate"
    end

    # Detect if this migration needs to run
    # Should return false if migration has already been applied
    # Must be implemented by subclasses
    # @return [Boolean] true if migration should proceed
    def migration_needed?
      raise NotImplementedError, "#{self.class} must implement #migration_needed?"
    end

    # === Run Mode Control ===
    # Migrations support dry-run mode (default) and actual-run mode (--run flag)

    # @return [Boolean] true if running in preview mode (no changes made)
    def dry_run?
      !options[:run]
    end

    # @return [Boolean] true if changes will actually be applied
    def actual_run?
      options[:run]
    end

    # Display banner indicating current run mode
    def run_mode_banner
      header("Running in #{dry_run? ? 'DRY RUN' : 'ACTUAL RUN'} mode")
      info("#{dry_run? ? 'No changes will be made' : 'Changes WILL be applied to the database'}")
      separator
    end

    # Execute block only if in actual run mode
    # Use this to wrap destructive operations
    # @yield Block to execute if in actual run mode
    # @return [Boolean] true if block was executed
    def for_realsies_this_time?
      if actual_run?
        yield
        true
      else
        false
      end
    end

    # Increment a named counter for migration statistics
    # @param key [Symbol] stat name to increment
    # @param increment [Integer] amount to add (default 1)
    def track_stat(key, increment = 1)
      @stats[key] += increment
    end

    # === Logging Methods ===
    # Consistent output formatting for migration scripts

    # Print prominent header message
    # @param message [String] text to display as header
    def header(message)
      OT.li(message.upcase)
    end

    # Print informational message
    # @param message [String] text to display
    def info(message)
      OT.li(message)
    end

    # Print debug message (only shown in debug mode)
    # @param message [String] text to display
    def debug(message)
      OT.ld(message)
    end

    # Add a visual separator line
    def separator
      '-' * 60
    end

    # Show progress for long-running operations
    # @param current [Integer] current item number
    # @param total [Integer] total items to process
    # @param message [String] operation description
    # @param step [Integer] how often to show progress (every N items)
    def progress(current, total, message = 'Processing', step = 100)
      if current % step == 0 || current == total
        OT.li "#{message} #{current}/#{total}..."
      end
    end

    # Display final migration summary
    # Yields to block for custom summary content
    def print_summary
      OT.li separator
      if dry_run?
        header('DRY RUN SUMMARY')
        yield(:dry_run) if block_given?
        info('To make actual changes, run with the --run option')
      else
        header('ACTUAL RUN SUMMARY')
        yield(:actual_run) if block_given?
      end
    end

    def migration_not_needed_banner
      info 'This usually means that the migration has already been applied.'
    end

    protected

    # Access to Redis database (defaults to DB 6)
    # @return [Redis] configured Redis connection
    def redis
      @redis ||= Familia.redis(6)
    end

    # Standard error logging for migrations
    # @param message [String] error description
    def error(message)
      OT.le(message)
    end
  end
end

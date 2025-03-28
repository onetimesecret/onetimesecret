# lib/onetime/migration.rb

module Onetime
  # Base class for all migrations
  class BaseMigration
    attr_accessor :options
    attr_reader :stats

    def initialize
      @options = {}
      @stats = Hash.new(0)
    end

    def self.run(options = {})
      migration = new
      migration.options = options
      migration.migrate
    end

    def migrate
      raise NotImplementedError, "#{self.class} must implement #migrate"
    end

    # Core run mode methods

    def dry_run?
      !options[:run]
    end

    def actual_run?
      options[:run]
    end

    def run_mode_banner
      header("Running in #{dry_run? ? 'DRY RUN' : 'ACTUAL RUN'} mode")
      info("#{dry_run? ? 'No changes will be made' : 'Changes WILL be applied to the database'}")
      separator
    end

    def execute_if_actual_run
      if actual_run?
        yield
        true
      else
        false
      end
    end

    def track_stat(key, increment = 1)
      @stats[key] += increment
    end

    # Logging and output methods

    def header(message)
      OT.li(message.upcase)
    end

    def info(message)
      OT.li(message)
    end

    def debug(message)
      OT.ld(message)
    end

    def separator
      OT.li("------------------------------------------------------------")
    end

    def progress(current, total, message = "Processing", step = 100)
      if current % step == 0 || current == total
        OT.li "#{message} #{current}/#{total}..."
      end
    end

    # Summary methods

    def print_summary
      separator
      if dry_run?
        header("DRY RUN SUMMARY")
        # Always show this message to make it clear how to run for real
        yield(:dry_run) if block_given?
        info("To make actual changes, run with the --run option")
      else
        header("ACTUAL RUN SUMMARY")
        yield(:actual_run) if block_given?
      end
    end

    protected

    def redis
      @redis ||= Familia.redis(6)
    end
  end
end

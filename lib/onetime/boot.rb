# lib/onetime/boot.rb
#
# frozen_string_literal: true

require_relative 'initializers'

module Onetime
  module Initializers
    @conf  = nil
    @ready = nil

    attr_reader :conf, :instance

    # Boot reads and interprets the configuration and applies it to the
    # relevant features and services. Must be called after applications
    # are loaded so that models have been required which is a pre-req
    # for attempting the database connection. Prior to that, Familia.members
    # is empty so we don't have any central list of models to work off
    # of.
    #
    # `mode` is a symbol, one of: :app, :cli, :test. It's used for logging
    # but otherwise doesn't do anything special (other than allow :cli to
    # continue even when it's cloudy with a chance of boot errors).
    #
    # When `db` is false, the database connections won't be initialized. This
    # is useful for testing or when you want to run code without necessary
    # loading all or any of the models.
    #
    def boot!(mode = nil, connect_to_db = true)
      OT.mode = mode unless mode.nil?
      OT.env  = ENV['RACK_ENV'] || 'production'

      # In test mode, silently return if already booted (idempotent)
      # In other environments, raise to catch unintended double-boot bugs
      if OT.ready?
        return if OT.testing?

        raise OT::Problem, 'Boot already completed'
      end

      # Sets a unique, 64-bit hexadecimal ID for this process instance.
      @instance ||= Familia.generate_trace_id.freeze

      # Track boot start time
      boot_start = Onetime.now_in_μs

      # Default to diagnostics disabled. FYI: in test mode, the test config
      # YAML has diagnostics enabled. But the DSN values are nil so it
      # doesn't get enabled even after loading config.
      OT.d9s_enabled = false

      # Normalize environment variables prior to loading the YAML config
      OT::Config.before_load

      # Loads the configuration and renders all value templates (ERB)
      raw_conf = OT::Config.load

      # SAFETY MEASURE: Freeze the (inevitably) shared config
      OT::Config.deep_freeze(raw_conf)

      # Normalize the configuration and make it available to the rest
      # of the initializers (via OT.conf).
      @conf = OT::Config.after_load(raw_conf)

      # Phase 1: Discovery - Initializer classes already loaded via require at top of file
      # (Each class auto-registers via inherited hook)

      # Phase 2: Loading - Instantiate and build dependency graph
      Boot::InitializerRegistry.load_all

      # Phase 3: Execution - Run initializers in dependency order (conditional on connect_to_db)
      if connect_to_db
        # Run all initializers in dependency order
        Boot::InitializerRegistry.run_all
      else
        # Run only non-database initializers
        ordered = Boot::InitializerRegistry.execution_order
        ordered.each do |init|
          # Skip database-related initializers
          next if [:configure_familia, :detect_legacy_data_and_warn,
                   :setup_connection_pool, :check_global_banner].include?(init.name)

          # Check if initializer wants to skip itself (e.g., feature disabled)
          if init.should_skip?
            init.skip!
            next
          end

          init.run(Boot::InitializerRegistry.context)
        end
      end

      # Verify registry health
      health = Boot::InitializerRegistry.health_check
      unless health[:healthy]
        failed = Boot::InitializerRegistry.initializers.select(&:failed?)
        failed_names = failed.map { |i| "#{i.name} (#{i.error.class}: #{i.error.message})" }
        raise OT::Problem, "Initializer(s) failed: #{failed_names.join(', ')}"
      end

      @ready = true if @ready.nil?

      # Log completion with timing
      boot_elapsed_ms = ((Onetime.now_in_μs - boot_start) / 1000.0).round
      OT.app_logger.info "Initialization complete (in #{boot_elapsed_ms}ms)"

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue OT::Problem => ex
      OT.le "Problem booting: #{ex}"
      OT.ld ex.backtrace.join("\n")

      # NOTE: Prefer `raise` over `exit` here. Previously we used
      # exit and it caused unexpected behaviour in tests, where
      # rspec for example would report all 5 examples passed even
      # though there were 30+ testcases defined in the file. There
      # were no log messages to indicate where the problem occurred
      # possibly because:
      #
      # 1. RSpec captures each example's STDOUT/STDERR and only prints it
      #    once the example finishes.
      # 2. Calling `exit` in the middle of an example kills the process
      #    immediately—any pending output (your `OT.le` message, buffered
      #    IO, etc.) never gets flushed back through RSpec's reporter.
      #
      # We were fortunate to find the issue via rspec. We had mocked
      # the connect_database method but also called the original:
      #
      # allow(Onetime).to receive(:connect_databases).and_call_original
      #
      raise ex unless mode?(:cli) # allows for debugging in the console
    rescue Redis::CannotConnectError => ex
      OT.le "Cannot connect to the database #{Familia.uri} (#{ex.class})"
      raise ex unless mode?(:cli)
    end

    # Replaces the global configuration instance with the provided data.
    def replace_config!(other)
      # TODO: Validate the new configuration data before replacing it
      self.conf = other
    end

    def ready?
      @ready == true
    end

    def not_ready
      @ready = false
    end

    private

    # Replaces the global configuration instance. This method is private to
    # prevent external modification of the shared configuration state
    # after initialization.
    def conf=(value)
      @conf = value
    end
  end

  extend Initializers
end

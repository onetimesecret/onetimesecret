# lib/onetime/boot.rb
#
# frozen_string_literal: true

require_relative 'initializers'

module Onetime
  module Initializers
    # Kubernetes-style boot state constants
    # Replaces ambiguous nil/true/false with explicit states
    BOOT_NOT_STARTED = :not_started  # boot! never called
    BOOT_STARTING    = :starting     # boot! in progress
    BOOT_STARTED     = :started      # boot! succeeded
    BOOT_FAILED      = :failed       # boot! failed with error

    @conf          = nil
    @boot_state    = nil  # Defaults to BOOT_NOT_STARTED via accessor
    @boot_error    = nil  # Stores error from failed boot
    @boot_registry = nil  # Instance-based registry (DI architecture)

    # Session configuration defaults
    # Ensures middleware always has valid values even if site.session is not configured
    SESSION_DEFAULTS = {
      'expire_after' => 86_400,      # 24 hours
      'key' => 'onetime.session',
      'same_site' => 'strict',
      'httponly' => true,
    }.freeze

    attr_reader :conf, :instance, :boot_registry, :boot_error

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

      # Kubernetes-style state guard with pattern matching (Ruby 3.0+)
      # Handles all four states explicitly to prevent ambiguity
      case [boot_state, OT.testing?]
      in [BOOT_STARTED, true]
        return  # Idempotent in test mode
      in [BOOT_STARTED, false]
        raise OT::Problem, 'Boot already completed'
      in [BOOT_STARTING, _]
        raise OT::Problem, 'Boot already in progress'
      in [BOOT_FAILED, true]
        reset_ready!  # Allow retry in test mode
      in [BOOT_FAILED, false]
        raise OT::Problem, "Boot previously failed: #{boot_error&.message}"
      else
        # BOOT_NOT_STARTED - proceed normally
      end

      starting!

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
      # Skip freezing in test mode to allow config modifications for test isolation.
      # Tests may need to modify config values without triggering FrozenError.
      OT::Config.deep_freeze(raw_conf) unless OT.testing?

      # Normalize the configuration and make it available to the rest
      # of the initializers (via OT.conf).
      @conf = OT::Config.after_load(raw_conf)

      # Phase 1: Create registry instance (pure DI architecture)
      @boot_registry = Boot::InitializerRegistry.new

      # Phase 2: Discovery + Loading - Find initializers via ObjectSpace, build dependency graph
      # Initializer classes were already required (lib/onetime/initializers.rb).
      @boot_registry.autodiscover

      # Phase 3: Execution - Run initializers in dependency order (conditional on connect_to_db)
      if connect_to_db
        # Run all initializers in dependency order
        @boot_registry.run_all
      else
        # Run only non-database initializers
        ordered = @boot_registry.execution_order
        ordered.each do |init|
          # Skip database-related initializers
          next if [:configure_familia, :detect_legacy_data_and_warn,
                   :setup_connection_pool, :check_global_banner].include?(init.name)

          # Check if initializer wants to skip itself (e.g., feature disabled)
          if init.should_skip?
            init.skip!
            next
          end

          init.run(@boot_registry.context)
        end
      end

      # Verify registry health
      health = @boot_registry.health_check
      unless health[:healthy]
        failed       = @boot_registry.initializers.select(&:failed?)
        failed_names = failed.map { |i| "#{i.name} (#{i.error.class}: #{i.error.message})" }
        raise OT::Problem, "Initializer(s) failed: #{failed_names.join(', ')}"
      end

      started!

      # Log completion with timing
      boot_elapsed_ms = ((Onetime.now_in_μs - boot_start) / 1000.0).round
      OT.boot_logger.info "--- Initialization complete (#{boot_elapsed_ms}ms)"

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue OT::Problem => ex
      failed!(ex)
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
      failed!(ex)
      OT.le "Cannot connect to the database #{Familia.uri} (#{ex.class})"
      raise ex unless mode?(:cli)
    end

    # Replaces the global configuration instance with the provided data.
    def replace_config!(other)
      self.conf = other
    end

    # Boot state accessor with default (Ruby 3.0+ endless method)
    def boot_state = @boot_state || BOOT_NOT_STARTED

    # State predicates (Ruby 3.0+ endless methods)
    def ready? = boot_state == BOOT_STARTED
    def boot_started? = boot_state == BOOT_STARTED
    def boot_starting? = boot_state == BOOT_STARTING
    def boot_failed? = boot_state == BOOT_FAILED
    def boot_not_started? = boot_state == BOOT_NOT_STARTED

    # State transitions
    def starting!
      @boot_state = BOOT_STARTING
      @boot_error = nil
    end

    def started!
      @boot_state = BOOT_STARTED
      @boot_error = nil
    end

    def failed!(error)
      @boot_state = BOOT_FAILED
      @boot_error = error
    end

    # Backward compatibility: marks as failed with explicit message
    def not_ready
      failed!(StandardError.new('Explicitly marked not ready'))
    end

    # Resets boot state to initial, allowing boot! to run again.
    # This is intended for test cleanup where tests manipulate boot state.
    def reset_ready!
      @boot_state = nil
      @boot_error = nil
    end

    # Session configuration accessor
    # Moved from auth.yaml to site config as sessions are auth-mode agnostic
    def session_config
      defaults = SESSION_DEFAULTS.dup
      session  = conf&.dig('site', 'session') || {}

      # Merge user config over defaults
      result = defaults.merge(session)

      # Fallback to site.secret if session secret is not set
      result['secret'] ||= conf&.dig('site', 'secret')

      # Apply SSL fallback if secure not explicitly set
      result['secure'] = ssl_enabled? if result['secure'].nil?

      result
    end

    private

    def ssl_enabled?
      conf&.dig('site', 'ssl') || env == 'production'
    end

    # Replaces the global configuration instance. This method is private to
    # prevent external modification of the shared configuration state
    # after initialization.
    def conf=(value)
      @conf = value
    end
  end

  extend Initializers
end

# lib/onetime/boot.rb

require 'onetime/refinements/hash_refinements'

require_relative 'initializers'

module Onetime
  @conf = nil
  @env = nil
  @mode = nil
  @debug = nil

  class << self

    attr_accessor :mode, :d9s_enabled
    attr_reader :configurator
    attr_writer :debug, :env, :global_secret
    attr_reader :conf, :instance, :i18n_enabled, :locales,
                :supported_locales, :default_locale, :fallback_locale,
                :global_banner, :rotated_secrets, :emailer, :first_boot

    using IndifferentHashAccess

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
    # Application models need to be loaded before booting so that each one gets
    # a database connection. It can't connect models it doesn't know about.
    #
    # Result**: OT.conf evolves from file-only → merged config during boot,
    # maintaining compatibility with all existing code that expects `OT.conf`
    # to be the single source of truth.
    def boot!(mode = :app, connect_to_db = true)
      @mode = mode

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this should be different for
      # each thread.
      @instance = [Process.pid.to_s, OT::VERSION.to_s].gibbler.short.freeze

      OT.ld "[BOOT] Initializing in '#{OT.mode}' mode (instance: #{@instance})"

      @configurator = OT::Config.load! do |config|
        OT.ld '[BOOT] Our own custom after load'
        modify_before_its_frozen(config)
      end

      OT.li "[BOOT] Configuration loaded from #{configurator.config_path}"

      # We have enough configuration to boot at this point. When do
      # merge with the configuration from the database? Or is that the
      # responsibility of the initializers? TODO: Find a way forward
      # NOTE: We need to reduce the number of initializers and make the run hotter
      #
      # Somewhere between here and:
      # apps/web/frontend/views/helpers/initialize_view_vars.rb
      #
      # In the current state of config that we have here, the app boots up
      # and serves requests (not the error middleware, gets passed that),
      # and then responds with 400 and an angry [view_vars] "Site config is
      # missing field: host".
      @conf = configurator.configuration

      # We can't do much without the initial file-based configuration. If it's
      # nil here it means that there's also no schema (which has the defaults).
      if OT.conf.nil?
        OT.le '[BOOT] Configuration failed to load and validate'
        OT.le '[BOOT] Has the schema been generated? Run `pnpm run schema:generate`'
        return # or raise?
      end

      # Initializers - simplified
      #
      # The registry was solving a problem you don't actually have. Your boot
      # sequence is fundamentally sequential, not a complex dependency graph.
      # The **module-per-initializer pattern** was solving the registry's
      # needs, not your actual needs.
      #
      # Phase 1: Basic setup
      # * Reads from file-based OT.conf (frozen)
      # * Writes to global OT attributes.
      run_phase1_initializers

      # Phase 2: Database + Config Merge
      # * Reads from database
      # * Replaces OT.conf with merged config
      run_phase2_initializers(connect_to_db)

      # Phase 3: Services (reads from merged OT.conf)
      run_phase3_initializers

      OT.ld '[BOOT] Completing initialization process...'
      Onetime.complete_initialization!
      OT.li "[BOOT] Startup completed successfully (instance: #{@instance})"

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue => error
      handle_boot_error(error)
    end

    def run_phase1_initializers
      load_locales        # OT.conf[:locales] -> OT.locales
      set_global_secret   # OT.conf[:site][:secret] -> OT.global_secret
      set_rotated_secrets # OT.conf[:site][:rotated_secrets] -> OT.rotated_secrets
      load_fortunes       # OT.conf[:fortunes] ->
    end

    def run_phase2_initializers
      if connect_to_db
        connect_databases
        setup_system_settings  # *** KEY: This updates @conf ***
        check_global_banner    # Uses merged OT.conf
      end
    end

    def run_phase3_initializers
      setup_authentication   # Uses merged OT.conf[:site][:authentication]
      setup_diagnostics     # Uses merged OT.conf[:diagnostics]
    end

    def safe_boot!(mode = nil, connect_to_db = true)
      boot!(mode, connect_to_db)
      true
    rescue => e
      # Boot errors are already logged in handle_boot_error
      OT.not_ready! # returns false
    end

    # Must return the whole modified config object
    def modify_before_its_frozen(config)
      # Modify the configuration before it is frozen
      config[:key] = 'value'
      config
    end

    private

    # def prepare_onetime_namespace(mode)
    #   @mode = mode unless mode.nil?
    #   @env = ENV['RACK_ENV'] || 'production'

    #   # Default to diagnostics disabled. FYI: in test mode, the test config
    #   # YAML has diagnostics enabled. But the DSN values are nil so it
    #   # doesn't get enabled even after loading config.
    #   @d9s_enabled = false

    # end

    def handle_boot_error(error)
      case error
      when OT::ConfigValidationError
        # ConfigValidationError includes detailed information about the error
        OT.le 'Configuration validation failed during boot'
        OT.le error.message
      when OT::ConfigError
        OT.le "Configuration error during boot: #{error.message}"
      when OT::Problem
        OT.le "Problem booting: #{error}"
        OT.ld error.backtrace.join("\n")
      when Redis::CannotConnectError
        OT.le "Cannot connect to Redis #{Familia.uri} (#{error.class})"
      else
        OT.le "Unexpected error during boot: #{error.class} - #{error.message}"
        OT.ld error.backtrace.join("\n")
      end

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
      # Only re-raise in app mode to stop the server. In test/cli mode,
      # we continue with reduced functionality.
      raise error unless mode?(:cli) || mode?(:test)
    end

  end
end

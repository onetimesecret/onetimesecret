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
    def boot!(mode = :app, connect_to_db = true)
      prepare_onetime_namespace(mode)
      OT.ld "[BOOT] Initializing Onetime application in '#{OT.mode}' mode"

      config = OT::Config.load!

      OT.li "[BOOT] Configuration loaded from #{config.config_path}"

      # TODO: Re-enable
      #
      # Run all registered initializers in TSort-determined order
      # Pass necessary context like mode and connect_to_db preference
      # Onetime::Initializers::Registry.run_all!({
      #   mode: OT.mode,
      #   connect_to_db: connect_to_db,
      #   config: conf,
      # })

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
      # and then responds with 400 and an angry [view_vars] "Site config is missing field: host"
      @conf = config.configuration

      if OT.conf.nil?
        OT.le '[BOOT] Configuration failed to load and validate'
        OT.le '[BOOT] Has the schema been generated? Run `pnpm run schema:generate`'
      else
        OT.ld '[BOOT] Completing initialization process...'
        Onetime.complete_initialization!
        OT.li "[BOOT] Startup completed successfully (instance: #{@instance})"
      end

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue => error
      handle_boot_error(error)
    end

    def safe_boot!(mode = nil, connect_to_db = true)
      boot!(mode, connect_to_db)
      true
    rescue => e
      # Boot errors are already logged in handle_boot_error
      OT.not_ready! # returns false
    end

    private

    def prepare_onetime_namespace(mode)
      @mode = mode unless mode.nil?
      @env = ENV['RACK_ENV'] || 'production'

      # Default to diagnostics disabled. FYI: in test mode, the test config
      # YAML has diagnostics enabled. But the DSN values are nil so it
      # doesn't get enabled even after loading config.
      @d9s_enabled = false

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this should be different for
      # each thread.
      @instance = [Process.pid.to_s, OT::VERSION.to_s].gibbler.freeze
    end

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
      when TSort::Cyclic
        # The detailed message from the registry's sorted_initializers will be part of e.message
        OT.le "Problem booting due to initializer dependency cycle: #{error.message}"
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

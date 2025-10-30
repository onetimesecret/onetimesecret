# frozen_string_literal: true

# lib/onetime/boot.rb

require_relative 'initializers'
require_relative 'boot/manifest'

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

      # Initialize boot manifest for structured progress tracking
      manifest = Boot::Manifest.new

      # Sets a unique, 64-bit hexadecimal ID for this process instance.
      @instance ||= Familia.generate_trace_id.freeze

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

      manifest.checkpoint(:config_load)

      # NOTE: We could benefit from tsort to make sure these
      # initializers are loaded in the correct order.
      load_locales

      configure_logging
      manifest.checkpoint(:logging_setup)
      manifest.logger = Onetime.boot_logger

      manifest.checkpoint(:diagnostics_init) do
        setup_diagnostics
      end

      set_global_secret
      set_rotated_secrets
      configure_domains
      configure_truemail
      load_fortunes
      setup_database_logging # meant to run regardless of db connection

      if connect_to_db
        manifest.checkpoint(:database_init) do
          detect_legacy_data_and_warn # must run before connect_databases
          connect_databases
          check_global_banner
        end
      end

      print_log_banner if $stdout.tty? && !mode?(:test) && !mode?(:cli)

      @ready = true if @ready.nil?

      # Display server ready milestone
      unless mode?(:test) || mode?(:cli)
        OT.log_box(['Initialization complete'])
      end

      manifest.checkpoint(:server_ready)
      manifest.complete!

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
    rescue StandardError => ex
      OT.le "Unexpected error", exception: ex
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

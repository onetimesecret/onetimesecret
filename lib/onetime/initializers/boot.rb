# lib/onetime/initializers/boot.rb

require 'sysinfo'

module Onetime
  module Initializers
    @sysinfo = nil
    @conf = nil

    attr_reader :conf, :instance, :sysinfo

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
    # NOTE: Should be called last in the list of onetime helpers.
    #
    def boot!(mode = nil, connect_to_db = true)
      OT.mode = mode unless mode.nil?
      OT.env = ENV['RACK_ENV'] || 'production'

      # Default to diagnostics disabled. FYI: in test mode, the test config
      # YAML has diagnostics enabled. But the DSN values are nil so it
      # doesn't get enabled even after loading config.
      OT.d9s_enabled = false

      @sysinfo ||= SysInfo.new.freeze

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this could different for
      # each thread.
      @instance ||= [OT.sysinfo.hostname, OT.sysinfo.user, Process.pid, OT::VERSION.to_s, OT.now.to_i].gibbler.freeze

      # Normalize environment variables prior to loading the YAML config
      OT::Config.before_load

      # Loads the configuration and renders all value templates (ERB)
      raw_conf = OT::Config.load

      # SAFETY MEASURE: Freeze the (inevitably) shared config
      OT::Config.deep_freeze(raw_conf)

      # Normalize the configuration and make it available to the rest
      # of the initializers (via OT.conf).
      @conf = OT::Config.after_load(raw_conf)

      # OT.conf is deeply frozen at this point which means that the
      # initializers are meant to read from it, set other values, but
      # not modify it.
      # TODO: Consider leaving unfrozen until the end of boot!

      # NOTE: We could benefit from tsort to make sure these
      # initializers are loaded in the correct order.
      load_locales
      set_global_secret
      set_rotated_secrets
      setup_authentication
      setup_diagnostics
      configure_domains
      configure_truemail
      prepare_emailers
      load_fortunes
      load_plans
      if connect_to_db
        connect_databases
        check_global_banner
      end

      # Setup system settings - check for existing override configuration
      # and merge with YAML config if present. Must happen before other
      # initializers that depend on the final merged configuration.
      setup_system_settings

      print_log_banner unless mode?(:test)

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil

    rescue OT::Problem => e
      OT.le "Problem booting: #{e}"
      OT.ld e.backtrace.join("\n")

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
      raise e unless mode?(:cli) # allows for debugging in the console

    rescue Redis::CannotConnectError => e
      OT.le "Cannot connect to redis #{Familia.uri} (#{e.class})"
      raise e unless mode?(:cli)

    rescue StandardError => e
      OT.le "Unexpected error `#{e}` (#{e.class})"
      OT.ld e.backtrace.join("\n")
      raise e unless mode?(:cli)
    end

    # Replaces the global configuration instance with the provided data.
    def replace_config!(other)
      # TODO: Validate the new configuration data before replacing it
      self.conf = other
    end

    private

    # Replaces the global configuration instance. This method is private to
    # prevent external modification of the shared configuration state
    # after initialization.
    def conf=(value)
      @conf = value
    end
  end
end

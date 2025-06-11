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
      # each thread. See tests/unit/ruby/rspec/puma_multi_process_spec.rb.
      @instance = [Process.pid.to_s, OT::VERSION.to_s].gibbler.short.freeze

      OT.ld "[BOOT] Initializing in '#{OT.mode}' mode (instance: #{@instance})"

      @configurator = OT::Configurator.load! do |conf|
        OT.ld '[BOOT] A chance to modify the conf hash before it is frozen'

        conf # must return the configuration hash
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
      require_relative 'initializers/phase1_before_database'
      run_phase1_initializers

      # Phase 2: Database + Config Merge
      # * Reads from database
      # * Replaces OT.conf with merged config
      if connect_to_db
        require_relative 'initializers/phase2_connect_database'
        run_phase2_initializers
      end

      # Phase 3: Services (reads from merged OT.conf)
      require_relative 'initializers/phase3_services'
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
    rescue => ex
      handle_boot_error(ex)
    end

    def safe_boot!(mode = nil, connect_to_db = true)
      boot!(mode, connect_to_db)
      true
    rescue => ex
      # Boot errors are already logged in handle_boot_error
      OT.not_ready! # returns false
    end

    private

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

__END__

#
# Work over these and at the bottom of config_module.rb.txt
#

def after_load
  # # Process colonels backwards compatibility
  # process_colonels_compatibility!(local_copy)

  # # Validate critical configuration
  # check_global_secret!(local_copy)

  # # Process authentication settings
  # process_authentication_settings!(local_copy)
end

def process_colonels_compatibility!(config)
  # Ensure site.authentication exists (using string keys)
  config['site'] ||= {}
  config['site']['authentication'] ||= {}

  # Handle colonels backwards compatibility (handle both symbol and string keys)
  root_colonels = config.delete('colonels') || config.delete(:colonels)
  auth_colonels = config['site']['authentication']['colonels']

  if auth_colonels.nil?
    # No colonels in authentication, use root colonels or empty array
    config['site']['authentication']['colonels'] = root_colonels || []
  elsif root_colonels
    # Combine existing auth colonels with root colonels
    config['site']['authentication']['colonels'] = auth_colonels + root_colonels
  end
end

def check_global_secret!(config)
  site_secret = config.dig('site', 'secret')
  if site_secret.nil? || site_secret == 'CHANGEME'
    raise OT::Problem, "Global secret cannot be nil or CHANGEME"
  end
end

def process_authentication_settings!(config)
  auth_config = config.dig('site', 'authentication')
  return unless auth_config

  # If authentication is disabled, set all auth sub-features to false
  unless auth_config['enabled']
    auth_config['colonels'] = false
    auth_config['signup'] = false
    auth_config['signin'] = false
    auth_config['autoverify'] = false
  end
end

# lib/onetime/boot.rb

require 'onetime/refinements/indifferent_hash_access'

require_relative 'boot/init_script_context'
require_relative 'services/system'

module Onetime
  @conf  = nil
  @env   = nil
  @mode  = nil
  @debug = nil

  class << self
    attr_accessor :d9s_enabled # rubocop:disable ThreadSafety/ClassAndModuleAttributes
    attr_reader :configurator, :conf, :instance, :i18n_enabled, :locales, :supported_locales, :default_locale, :fallback_locale, :global_banner, :rotated_secrets, :emailer, :first_boot, :mode
    attr_writer :debug, :env, :global_secret # rubocop:disable ThreadSafety/ClassAndModuleAttributes

    def boot!(*)
      Boot.boot!(*)
    end

    def safe_boot!(*)
      boot!(*)
      true
    rescue StandardError
      # Boot errors are already logged in handle_boot_error
      OT.not_ready! # returns false
    ensure
      # We can't do much without the initial file-based configuration. If it's
      # nil here it means that there's also no schema (which has the defaults).
      if OT.conf.nil?
        OT.le '-' * 70
        OT.le '[BOOT] Configuration failed to load and validate'
        OT.le '[BOOT] Has the schema been generated? Run `pnpm run schema:generate`'
        OT.le '-' * 70
        nil
      end
    end

    def set_boot_state(mode, instanceid, env)
      @mode       = mode || :app
      @instance   = instanceid # TODO: rename OT.instance -> instanceid
      @env        = env || :production
    end

  end

  module Boot
    extend self

    @init_scripts_dir = File.join(Onetime::HOME, 'etc', 'init.d').freeze

    attr_reader :init_scripts_dir, :configurator

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
    def boot!(mode = nil, connect_to_db = true)

      env = (ENV['RACK_ENV'] || 'production').downcase

      # Sets a unique SHA hash every time this process starts. In a multi-
      # threaded environment (e.g. with Puma), this should be different for
      # each thread. See tests/unit/ruby/rspec/puma_multi_process_spec.rb.
      instanceid = [Process.pid.to_s, OT::VERSION.to_s].gibbler.short.freeze

      Onetime.set_boot_state(mode, instanceid, env)

      OT.ld "[BOOT] Initializing in '#{OT.mode}' mode (instance: #{instanceid})"

      @configurator = OT::Configurator.load! do |config|
        OT.ld '[BOOT] Processing hook - config transformations before final freeze'
        run_init_scripts(config,
          mode: OT.mode,
          instanceid: instanceid, # these are passed directly to each script
          connect_to_db: connect_to_db,
        )
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

      OT.ld '[BOOT] Completing initialization process...'
      Onetime.complete_initialization!
      OT.li "[BOOT] Startup completed successfully (instance: #{instanceid})"

      # Let's be clear about returning the prepared configruation. Previously
      # we returned @conf here which was confusing because already made it
      # available above. Now it is clear that the only way the rest of the
      # code in the application has access to the processed configuration
      # is from within this boot! method.
      nil
    rescue StandardError => ex
      handle_boot_error(ex)
    end

    private

    # Runs init.d scripts for each config section during the processing hook phase.
    # Config is still mutable - these scripts can modify their section's config,
    # register routes, set feature flags, etc. One script per config section.
    #
    # Different from onetime/services/system which run AFTER config is frozen and
    # handle system-wide services (Redis, databases, emailer, etc).
    def run_init_scripts(config_being_processed, **)
      base_path = init_scripts_dir
      return unless Dir.exist?(base_path)

      # Loop through each of the top-level config sections
      #
      # Only run scripts that exist
      run_these_scripts = config_being_processed.keys
        .map { |key| [key, File.join(base_path, "#{key}.rb")] }
        .select { |_, path| File.exist?(path) }
        .to_h

      return if run_these_scripts.empty? # there were no actual files

      OT.ld "[BOOT] Starting init script processing phase for: #{run_these_scripts.keys.join(', ')}."

      # Runs init.d scripts for each config section during the processing hook phase.
      # Config is still mutable - these scripts can modify their section's config,
      # register routes, set feature flags, etc. One script per config section.
      #
      # Different from onetime/services/system which run AFTER config is frozen and
      # handle system-wide services (Redis, databases, emailer, etc).
      # e.g. site, storage, i18n, ...
      run_these_scripts.each do |section_key, file_path|
        run_init_script(config_being_processed, section_key, file_path, **)

      rescue StandardError
        OT.le <<~MSG
          [BOOT] ERROR:
            Unhandled exception during init script processing.
            Halting further init scripts.
        MSG
        # The specific error details (class, message, backtrace) will be
        # logged by handle_boot_error
        raise
      end

      OT.li '[BOOT] Successfully completed init script processing phase.'
    end

    # File existence is already checked by the scripts_to_run filter
    def run_init_script(config_being_processed, section_key, file_path, **)
      OT.ld "[BOOT] Preparing to execute init script for section: '#{section_key}' (from #{file_path})"

      # Create a frozen snapshot of the *current* state of the main config
      # This snapshot includes changes from any previous scripts in this loop.
      global_snapshot        = OT::Utils.deep_freeze(config_being_processed, clone: true)
      current_section_config = config_being_processed[section_key] # still original reference

      # Create context for script execution, passing along the
      # variables that it'll have access to.
      context = OT::Boot::InitScriptContext.new(
        current_section_config, # mutable
        section_key,
        global_snapshot,        # includes updated previous section but immutable
        ** # rubocop:disable Style/TrailingCommaInArguments
      )

      execute_script_with_context(file_path, context)
      OT.ld "[BOOT] Finished processing init script for section: '#{section_key}'."
    end

    def execute_script_with_context(file_path, context)
      # The load method hands rescuing SystemExit to prevent an init script
      # from completely derailing the boot process (even by accident).
      # Technically it's no less secure than reading a ruby file in a
      # different branch of the project, but since it sits near the YAML
      # configuration file, it is more exposed to tomfoolery.
      OT.ld "[BOOT] Executing: #{context.section_key} (file: #{file_path})"
      OT::Configurator::Load.ruby_load_file(file_path, context)

    rescue SystemExit => ex
      # Log that a script attempted to exit, then continue to the next script in the loop
      OT.li "[BOOT] Init script '#{context.section_key}' (from #{file_path}) called exit(#{ex.status}). Handled; boot sequence continues."
      # Any other StandardError will propagate up to run_init_scripts's rescue block
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
      else
        codepath = OT.debug? ? error.backtrace : error.backtrace[0..0]
        OT.le <<~MSG
          Unexpected error during boot (#{error.class}):

          #{error.message}
          #{codepath.join("\n")}

        MSG
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

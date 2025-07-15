# lib/onetime/boot.rb

require 'concurrent'

require_relative 'boot/init_script_context'
require_relative 'services/config_proxy'
require_relative 'services/system'

module Onetime
  # Boot orchestrates the application startup sequence: configuration loading,
  # init script execution, and service initialization. Think of it as the
  # emcee for getting your Onetime instance up and running.
  module Boot
    extend self

    @init_scripts_dir = File.join(Onetime::HOME, 'etc', 'init.d').freeze

    attr_reader :init_scripts_dir, :configurator

    # Boots the Onetime application.
    #
    # This method must be called after application models are loaded so that
    # database connections can be established for all known models.
    #
    # The configuration evolves from file-only to a merged, validated config
    # during boot, eventually made available application-wide via `OT.conf`.
    #
    # @param mode [Symbol, nil] The runtime mode (:app, :cli, :test). Affects
    #   logging and error handling (e.g., :cli allows continuing on boot errors).
    # @param connect_to_db [Boolean] Whether to initialize database connections.
    #   Useful for testing or when models are not needed.
    # @return [nil]
    # @raise [OT::ConfigError] If initialization scripts fail.
    #
    # This method orchestrates the entire application startup sequence:
    # 1. Generates a unique instance ID
    # 2. Sets the boot state
    # 3. Loads configuration
    # 4. Runs initialization scripts
    # 5. Starts system services
    # 6. Sets up global configuration proxy (`OT.conf`)
    #
    # @example
    #   Onetime::Boot.boot!(:app)  # Boot in application mode
    #   Onetime::Boot.boot!(:test, false)  # Boot in test mode without DB connection
    def boot!(mode = nil, connect_to_db = true)
      # Sets a unique SHA hash for this process instance.
      instanceid = [OT::VERSION.to_s, Process.pid.to_s].gibbler.shorten.freeze

      Onetime.set_boot_state(mode, instanceid)

      OT.ld "[BOOT] Initializing in '#{OT.mode}' mode (instance: #{instanceid})"

      script_options = {
        mode: OT.mode,
        instanceid: instanceid,
        connect_to_db: connect_to_db,
      }

      @configurator = OT::Configurator.load! do |config|
        OT.ld '[BOOT] Processing hook - config transformations before final freeze'
        unless run_init_scripts(config, **script_options)
          raise OT::ConfigError, 'Initialization scripts failed'
        end
      end

      # `configurator.configuration` returns a fresh, frozen  deep_clone of the
      # processed configuration hash.
      config = configurator.configuration

      OT.ld "[BOOT] Configuration from #{configurator.config_path} is now frozen"

      OT.ld '[BOOT] Starting system services...'

      # We pass the static `config` to the services since they don't need to go
      # through the ConfigProxy on account of knowing how to access the
      # ServiceRegistry.app_state if necessary.
      OT::Services::System.start_all(config, connect_to_db: connect_to_db)

      if OT::Services::ServiceRegistry.ready?
        OT.ld '[BOOT] Completing initialization process...'

        # With services healthy, create ConfigProxy and make `OT.conf` available.
        Onetime.set_config_proxy(Services::ConfigProxy.new(config))

      else
        OT.le '[BOOT] System services failed to start'
        OT.le '[BOOT] This means OT.conf and friends are not available'
        return
      end

      Onetime.complete_initialization!

      OT.ld "[BOOT] Startup completed successfully (instance: #{instanceid})"

      # The processed configuration is already made available globally via
      # `OT.conf`. Returning nil reinforces that the return value of `boot!`
      # is not the config itself.
      nil
    rescue StandardError => ex
      handle_boot_error(ex)
    end

    private

    # Runs initialization scripts for each configuration section.
    #
    # This method handles a processing hook phase where:
    # - Configuration is still mutable, allowing scripts to modify config sections.
    # - Scripts can register routes or set feature flags.
    # This differs from system services, which run *after* config is frozen.
    #
    # @param config_being_processed [Hash] The mutable configuration during processing.
    # @param ** [Hash] Additional options to pass to init scripts.
    # @return [Boolean] Whether all init scripts ran successfully.
    # @note Only runs scripts that correspond to existing config sections.
    def run_init_scripts(config_being_processed, **)
      base_path = init_scripts_dir
      return unless Dir.exist?(base_path)

      run_these_scripts = config_being_processed.keys
        .map { |key| [key, File.join(base_path, "#{key}.rb")] }
        .select { |_, path| File.exist?(path) }
        .to_h

      return if run_these_scripts.empty? # there were no actual files

      OT.ld "[BOOT] Starting init script phase for: #{run_these_scripts.keys.join(', ')}."

      # Runs etc/init.d scripts for each config section during the processing
      # hook phase. Config is still mutable - these scripts can modify their
      # section's config, register routes, set feature flags, etc. One script
      # per config section.
      #
      # Different from onetime/services/system which run AFTER config is frozen
      # and handle system-wide services (Redis, databases, emailer, etc).
      # e.g. site, storage, i18n, ...
      run_these_scripts.each do |section_key, file_path|
        run_init_script(config_being_processed, section_key, file_path, **)
      rescue StandardError
        OT.le <<~MSG
          [BOOT] ERROR:
            Unhandled exception during init script processing.
            Halting further init scripts.
        MSG
        # The specific error details will be logged by handle_boot_error
        raise
      rescue SystemExit => ex
        # Log that a script attempted to exit, then continue to the next script in the loop
        OT.li <<~MSG
          [BOOT] Init script '#{section_key}' (from #{file_path}) called exit(#{ex.status}).
                 Skipping remaining scripts.
        MSG
        return false
      end

      OT.ld '[BOOT] Completed init script processing phase.'
      true
    end

    # Executes a single init script for the given config section.
    def run_init_script(config_being_processed, section_key, file_path, **)
      pretty_path = Onetime::Utils.pretty_path(file_path)
      OT.ld "[BOOT] Preparing '#{section_key}' init script (#{pretty_path})"

      # Create a frozen snapshot of the *current* state of the main config,
      # including changes from any previous scripts in this loop.
      global_snapshot        = OT::Utils.deep_freeze(config_being_processed, clone: true)
      current_section_config = config_being_processed[section_key] # still original reference

      # Create context for script execution, passing along accessible variables.
      context = OT::Boot::InitScriptContext.new(
        current_section_config, # mutable
        section_key,
        global_snapshot,        # immutable snapshot of global config
        ** # rubocop:disable Style/TrailingCommaInArguments
      )

      execute_script_with_context(file_path, context)
      OT.ld "[BOOT] Finished processing '#{section_key}' init script."
    end

    # Loads and executes a Ruby init script within the provided context.
    # Handles SystemExit to prevent scripts from derailing boot.
    def execute_script_with_context(file_path, context)
      # The `ruby_load_file` method rescues `SystemExit` to prevent a script
      # from completely derailing the boot process (even by accident).
      pretty_path = Onetime::Utils.pretty_path(file_path)
      OT.ld "[BOOT] Executing '#{context.section_key}' init script (#{pretty_path})"
      OT::Configurator::Load.ruby_load_file(file_path, context)

      # Allow exceptions (including SystemExit) to be handled up the chain
      # where it can decide whether to continue running the remaining scripts.
    end

    # Handles errors that occur during the application boot process.
    #
    # Provides graceful error handling with different logging strategies:
    # - Logs configuration validation errors.
    # - Handles specific error types with appropriate logging.
    # - Provides detailed error information in debug mode.
    #
    # Error handling behavior varies based on runtime mode:
    # - In CLI or test mode: Continues with reduced functionality.
    # - In app mode: Stops the server by re-raising the error.
    #
    # @param error [StandardError] The error encountered during boot.
    # @raise [StandardError] Re-raises the error in `:app` mode.
    # @note Prefers raising errors over exiting to preserve test and logging behavior.
    def handle_boot_error(error)
      case error
      when OT::ConfigValidationError, OT::ConfigError
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

      raise error unless OT.mode?(:cli) || OT.mode?(:test)
    end
  end

  # Immediate loading - static configuration is available as soon as the module loads.
  @static_config = begin
    Onetime::Configurator.load_with_impunity!
  rescue StandardError => ex
    puts "Failed to load static config: #{ex.message}"
    OT.ld(ex.backtrace)
    exit 1
  end
end

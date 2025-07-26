# lib/onetime.rb

require_relative 'onetime/constants'

module Onetime
  # Runtime environment mode and configuration settings
  #
  # @!attribute [r] mode
  #   @return [Symbol, nil] The current runtime mode (:app, :cli, :test)
  # @!attribute [r] env
  #   @return [String] The current environment (production, development, test)
  # @!attribute [r] debug
  #   @return [Boolean] Whether debug mode is enabled
  @mode  = nil
  @env   = (ENV['RACK_ENV'] || 'production').downcase.freeze
  @debug = ENV['ONETIME_DEBUG'].to_s.match?(/^(true|1)$/i).freeze

  # Global configuration management with unified access to static and dynamic settings
  #
  # @note Provides a consistent configuration interface across the application lifecycle
  #
  # Key Principles:
  # - Always returns a configuration (never nil)
  # - Separates static configuration from system readiness
  # - Supports both pre-boot and post-boot configuration access
  #
  # Lifecycle:
  # 1. Static configuration loaded immediately on module load
  # 2. Boot process replaces static config with fully initialized ConfigProxy
  #
  # @see Onetime::Boot The boot process that initializes the configuration
  @mutex        = Mutex.new
  @config_proxy = nil

  class << self
    attr_reader :mode, :debug, :env, :config_proxy, :instance, :static_config

    # Boots the application with full initialization
    #
    # @param args [Array] Arguments to pass to the boot process
    # @return [Onetime] Self, allowing method chaining
    def boot!(*)
      Boot.boot!(*)
      self
    end

    # Safely boots the application with error handling
    #
    # @param args [Array] Arguments to pass to the boot process
    # @return [Boolean, nil]
    #   - true if boot succeeds
    #   - false if boot fails (via OT.not_ready!)
    #   - nil if configuration cannot be loaded
    #
    # @note Provides a more forgiving boot process compared to boot!
    # @see boot! The standard boot method
    def safe_boot!(*)
      Boot.boot!(*)
      true
    rescue StandardError
      # Boot errors are already logged in handle_boot_error
      OT.not_ready! # returns false
    ensure
      # We can't do much without the initial file-based configuration. If it's
      # nil here it means that there's also no schema (which has the defaults).
      if OT.conf.nil?
        OT.le '-' * 70
        OT.le '[BOOT] Configuration failed to load and validate. If there are no'
        OT.le '[BOOT] error messages above, run again with ONETIME_DEBUG=1 and/or'
        OT.le '[BOOT] make sure the config schema exists. Run `pnpm run schema:generate`'
        OT.le '-' * 70
        nil
      end
    end

    # Retrieves the current application configuration
    #
    # Provides a fallback mechanism for configuration access:
    # 1. Returns ConfigProxy if available
    # 2. Falls back to static configuration
    # 3. Returns an empty hash if no configuration is present
    #
    # @return [Hash] The current configuration
    # @note Ensures configuration is always accessible, even before full boot
    def conf
      config_proxy || @static_config || {}
    end

    # Retrieves the current application state from the ServiceRegistry
    #
    # @return [Hash] The current application state
    # @note Returns an empty hash if the application is not fully initialized
    #
    # Design Considerations:
    # - Only provides state after successful boot
    # - Prevents access to state before system is ready
    # - Calling code is responsible for checking readiness
    def state
      # TODO: Evaluate the need for readiness check
      # Rationale: Service registry state is specific to the boot process
      # and should not be accessed before full initialization
      ready? ? Onetime::Services::ServiceRegistry.state : {}
    end

    # Retrieves the current service providers from the ServiceRegistry
    #
    # @return [Hash] The current service providers
    # @note Returns an empty hash if the application is not fully initialized
    #
    # Similar design principles to #state method
    def providers
      ready? ? Onetime::Services::ServiceRegistry.provider_keys : []
    end

    # Sets the global configuration proxy in a thread-safe manner
    #
    # @param config_proxy [Onetime::Services::ConfigProxy] The configuration proxy to set
    # @note Ensures thread-safe update of the global configuration proxy
    def set_config_proxy(config_proxy)
      @mutex.synchronize do
        @config_proxy = config_proxy
      end
    end

    # Sets the boot state and instance identifier in a thread-safe manner
    #
    # @param mode [Symbol] The runtime mode (:app, :cli, :test)
    # @param instanceid [String] A unique identifier for the current process instance
    # @note Ensures thread-safe update of runtime mode and instance identifier
    # @todo Rename @instance to @instanceid for clarity
    def set_boot_state(mode, instanceid)
      @mutex.synchronize do
        @mode       = mode || :app
        @instance   = instanceid # TODO: rename OT.instance -> instanceid
      end
    end
  end
end

require_relative 'onetime/class_methods'
require_relative 'onetime/errors'
require_relative 'onetime/version'
require_relative 'onetime/cluster'
require_relative 'onetime/configurator'
require_relative 'onetime/mail'
require_relative 'onetime/alias'
require_relative 'onetime/ready'
require_relative 'onetime/boot'

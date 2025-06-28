# lib/onetime.rb

require_relative 'onetime/constants'

module Onetime
  @mode  = nil
  @env   = (ENV['RACK_ENV'] || 'production').downcase.freeze
  @debug = ENV['ONETIME_DEBUG'].to_s.match?(/^(true|1)$/i).freeze

  # Contains the global instance of ConfigProxy which is set at boot-time
  # and lives for the duration of the process. Accessed externally via
  # `Onetime.conf` method.
  #
  # Provides unified access to both static and dynamic configuration.
  #
  # NOTE: The distinction between static configuration (essential settings
  # needed for basic operation) and system readiness (fully initialized,
  # validated, and operational state. These are separate concerns. OT.conf
  # should always return some level of configuration. IOW, we generally
  # shouldn't write code that deals with OT.conf being nil. The exception is
  # the code that runs immediately at process start and the tests relevant
  # to that specific behaviour.
  #
  @mutex        = Mutex.new
  @config_proxy = nil

  class << self
    attr_reader :mode, :debug, :env, :config_proxy, :instance, :static_config

    def boot!(*)
      Boot.boot!(*)
      self
    end

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

    # A convenience method for accessing the configuration proxy.
    #
    # Before ConfigProxy instance is available, fails over to static config.
    def conf
      config_proxy || @static_config || {}
    end

    # A convenience method for accessing the ServiceRegistry application state.
    def state
      # TODO: Is it okay/reasonable to check the readiness here? I think so b/c
      # the service registry state is 1) new, so older code doesn't depend on it
      # and 2) it is a specific reason for and result of the full boot initialization
      # process. There is no notion of a service registry state before boot. Or
      # to put it another way, code that runs prior to boot should not be
      # depending on the service registry state.
      #
      # So then the question becomes: should we check readiness here to decide
      # what to return or simply return nil. It's the responsibility of the
      # calling code to check readiness before accessing the state.
      ready? ? Onetime::Services::ServiceRegistry.state : {}
    end

    # A convenience method for accessing the ServiceRegistry providers.
    def provider
      # Ditto
      ready? ? Onetime::Services::ServiceRegistry.provider : {}
    end

    def set_config_proxy(config_proxy)
      @mutex.synchronize do
        @config_proxy = config_proxy
      end
    end

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

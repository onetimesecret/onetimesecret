# lib/onetime/config.rb

module Onetime
  module Config
    extend self

    unless defined?(SERVICE_PATHS)
      SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
      UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
      DEFAULTS = {
        site: {
          secret: nil,
          domains: { enabled: false },
          regions: { enabled: false },
          plans: { enabled: false },
          secret_options: {
            default_ttl: 7.days,
            ttl_options: [
              60.seconds,     # 60 seconds (was missing from v0.20.5)
              5.minutes,      # 300 seconds
              30.minutes,     # 1800
              1.hour,         # 3600
              4.hours,        # 14400
              12.hours,       # 43200
              1.day,          # 86400
              3.days,         # 259200
              1.week,         # 604800
              2.weeks,        # 1209600
              30.days,        # 2592000
            ]
          },
          interface: {
            ui: { enabled: true },
            api: { enabled: true },
          },
          authentication: {
            enabled: true,
            colonels: [],
          },
        },
        internationalization: {
          enabled: false,
          default_locale: 'en',
        },
        mail: {},
        logging: {
          http_requests: true,
        },
        diagnostics: {
          enabled: false,
        },
        development: {
          enabled: false,
          frontend_host: '',
        },
        experimental: {
          allow_nil_global_secret: false, # defaults to a secure setting
          rotated_secrets: [],
        },
      }

    end

    attr_reader :env, :base, :bootstrap
    attr_writer :path

    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    def before_load
      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      ENV['REGIONS_ENABLED'] = ENV.values_at('REGIONS_ENABLED', 'REGIONS_ENABLE').compact.first || 'false'
    end

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def load(path=nil)
      path ||= self.path

      raise ArgumentError, "Missing config file" if path.nil?
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)

      parsed_template = ERB.new(File.read(path))

      YAML.load(parsed_template.result)
    rescue StandardError => e
      OT.le "Error loading config: #{path}"

      # Log the contents of the parsed template for debugging purposes.
      # This helps identify issues with template rendering and provides
      # context for the error, making it easier to diagnose config
      # problems, especially when the error involves environment vars.
      if OT.debug? && parsed_template
        template_lines = parsed_template.result.split("\n")
        template_lines.each_with_index do |line, index|
          OT.ld "Line #{index + 1}: #{line}"
        end
      end

      OT.le e.message
      OT.le e.backtrace.join("\n")
      raise OT::ConfigError.new(e.message)
    end

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # @param incoming_config [Hash] The loaded, unprocessed configuration hash in raw form
    # @return [Hash] The processed configuration hash with defaults applied and security measures in place
    def after_load(incoming_config)

      # SAFETY MEASURE: Freeze the incoming (presumably) shared config
      # We check for settings in the frozen raw config where we can be sure that
      # its values are directly from the actual config file -- without any
      # normalization or other manipulation.
      deep_freeze(incoming_config)

      # SAFETY MEASURE: Deep Copy Protection
      # Create a deep copy of the configuration to prevent unintended mutations
      # This protects against side effects when multiple components access the same config
      # Without this, modifications to the config in one component could affect others.
      conf = if incoming_config.nil?
        {}
      else
        Marshal.load(Marshal.dump(incoming_config))
      end

      # SAFETY MEASURE: Validation and Default Security Settings
      # Ensure all critical security-related configurations exist
      conf = deep_merge(DEFAULTS, conf) # TODO: We don't need to re-assign `conf`

      raise_concerns(conf)

      # Disable all authentication sub-features when main feature is off for
      # consistency, security, and to prevent unexpected behavior. Ensures clean
      # config state.
      # NOTE: Needs to run after other site.authentication logic
      if conf.dig(:site, :authentication, :enabled) != true
        conf[:site][:authentication].each_key do |key|
          conf[:site][:authentication][key] = false
        end
      end

      # Combine colonels from root level and authentication section
      # This handles the legacy config where colonels were at the root level
      # while ensuring we don't lose any colonels from either location
      root_colonels = conf.fetch(:colonels, [])
      auth_colonels = conf.dig(:site, :authentication, :colonels) || []
      conf[:site][:authentication][:colonels] = (root_colonels + auth_colonels).compact.uniq

      ttl_options = conf.dig(:site, :secret_options, :ttl_options)
      default_ttl = conf.dig(:site, :secret_options, :default_ttl)

      # if the ttl_options setting is a string, we want to split it into an
      # array of integers.
      if ttl_options.is_a?(String)
        conf[:site][:secret_options][:ttl_options] = ttl_options.split(/\s+/)
      end
      ttl_options = conf.dig(:site, :secret_options, :ttl_options)
      if ttl_options.is_a?(Array)
        conf[:site][:secret_options][:ttl_options] = ttl_options.map(&:to_i)
      end

      if default_ttl.is_a?(String)
        conf[:site][:secret_options][:default_ttl] = default_ttl.to_i
      end

      # TODO: Move to an initializer
      if conf.dig(:site, :plans, :enabled).to_s == "true"
        stripe_key = conf.dig(:site, :plans, :stripe_key)
        unless stripe_key
          raise OT::Problem, "No `site.plans.stripe_key` found in #{path}"
        end

        require 'stripe'
        Stripe.api_key = stripe_key
      end

      # Apply the defaults to sentry backend and frontend configs
      # and set our local config with the merged values.
      diagnostics = incoming_config.fetch(:diagnostics, {})
      conf[:diagnostics] = {
        enabled: diagnostics[:enabled] || false,
        sentry: apply_defaults(diagnostics[:sentry]),
      }
      conf[:diagnostics][:sentry][:backend] ||= {}

      # Update global diagnostic flag based on config
      backend_dsn = conf.dig(:diagnostics, :sentry, :backend, :dsn)
      frontend_dsn = conf.dig(:diagnostics, :sentry, :frontend, :dsn)
      # It's disabled when no DSN is present, regardless of enabled setting

      Onetime.d9s_enabled = !!(conf.dig(:diagnostics, :enabled) && (backend_dsn || frontend_dsn))

      # SECURITY MEASURE #4: Configuration Immutability
      # Freeze the entire configuration recursively to prevent modifications
      # This ensures configuration immutability and protects against
      # accidental or malicious changes after loading
      #
      # Why this matters:
      # - Prevents runtime modification of sensitive values like secrets and API keys
      # - Any attempt to modify frozen config will raise a FrozenError, failing fast
      # - Guarantees configuration integrity throughout application lifecycle
      # - Makes security guarantees stronger by ensuring config values can't be tampered with
      deep_freeze(conf)
    end

    def raise_concerns(conf)

      # SAFETY MEASURE: Critical Secret Validation
      # Handle potential nil global secret
      # The global secret is critical for encrypting/decrypting secrets
      # Running without a global secret is only permitted in exceptional cases
      allow_nil = conf.dig(:experimental, :allow_nil_global_secret) || false
      global_secret = conf[:site].fetch(:secret, nil)
      global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

      # Onetime.global_secret is set in the initializer set_global_secret

      if global_secret.nil?
        unless allow_nil
          # Fast fail when global secret is nil and not explicitly allowed
          # This is a critical security check that prevents running without encryption
          raise OT::ConfigError, "Global secret cannot be nil - set SECRET env var or site.secret in config"
        end

        # SAFETY MEASURE: Security Warnings for Dangerous Configurations
        # Security warning when proceeding with nil global secret
        # These warnings are prominently displayed to ensure administrators
        # understand the security implications of their configuration
        OT.li "!" * 50
        OT.li "SECURITY WARNING: Running with nil global secret!"
        OT.li "This configuration presents serious security risks:"
        OT.li "- Secret encryption will be compromised"
        OT.li "- Data cannot be properly protected"
        OT.li "- Only use during recovery or transition periods"
        OT.li "Set valid SECRET env var or site.secret in config ASAP"
        OT.li "!" * 50
      end

      unless conf[:site]&.key?(:authentication)
        raise OT::ConfigError, "No `site.authentication` config found in #{path}"
      end

      unless conf.key?(:mail)
        raise OT::ConfigError, "No `mail` config found in #{path}"
      end

      unless conf[:mail].key?(:truemail)
        raise OT::ConfigError, "No TrueMail config found"
      end
    end

    def exists?
      !path.nil?
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= find_configs.first
    end

    def mapped_key(key)
      # `key` is a symbol. Returns a symbol.
      # If the key is not in the KEY_MAP, return the key itself.
      KEY_MAP[key] || key
    end

    # Recursively freezes an object and all its nested components
    # to ensure complete immutability. This is a critical security
    # measure that prevents any modification of configuration values
    # after they've been loaded and validated, protecting against both
    # accidental mutations and potential security exploits.
    #
    # @param obj [Object] The object to freeze
    # @return [Object] The frozen object
    # @security This ensures configuration values cannot be tampered with at runtime
    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
      when Array
        obj.each { |v| deep_freeze(v) }
      end
      obj.freeze
    end

    # Creates a complete deep copy of a configuration hash using Marshal
    # dump and load. This ensures all nested objects are properly duplicated,
    # preventing unintended sharing of references that could lead to data
    # corruption if modified.
    #
    # @param config_hash [Hash] The configuration hash to be cloned
    # @return [Hash] A deep copy of the original configuration hash
    # @raise [OT::Problem] When Marshal serialization fails due to unserializable objects
    # @security Prevents configuration mutations from affecting multiple components
    #
    # @limitations
    #   This method has significant limitations due to its reliance on Marshal:
    #   - Cannot clone objects with singleton methods, procs, lambdas, or IO objects
    #   - Will fail when encountering objects that implement custom _dump methods without _load
    #   - Loses any non-serializable attributes from complex objects
    #   - May not preserve class/module references across different Ruby processes
    #   - Thread-safety issues may arise with concurrent serialization operations
    #   - Performance can degrade with deeply nested or large object structures
    #
    #   Consider using a recursive approach for specialized object cloning when
    #   dealing with configuration containing custom objects, procs, or other
    #   non-serializable elements. For critical security contexts, validate that
    #   all configuration elements are serializable before using this method.
    #
    def deep_clone(config_hash)
      Marshal.load(Marshal.dump(config_hash))
    rescue TypeError => ex
      raise OT::Problem, "[deep_clone] #{ex.message}"
    end

    def deep_clone(config_hash)
      Marshal.load(Marshal.dump(config_hash))
    rescue TypeError => ex
      raise OT::Problem, "[deep_clone] #{ex.message}"
    end

    # Applies default values to configuration sections.
    #
    # @param config [Hash] Configuration with top-level section keys, including a :defaults key
    # @return [Hash] Configuration with defaults applied to each section, with :defaults removed
    #
    # This method extracts defaults from the :defaults key and applies them to each section:
    # - Section values override defaults (except nil values, which use defaults)
    # - The :defaults section is removed from the result
    # - Only Hash-type sections receive defaults
    #
    # @example Basic usage
    #   config = {
    #     defaults: { timeout: 5, enabled: true },
    #     api: { timeout: 10 },
    #     web: { theme: 'dark' }
    #   }
    #   apply_defaults(config)
    #   # => { api: { timeout: 10, enabled: true },
    #   #      web: { theme: 'dark', timeout: 5, enabled: true } }
    #
    # @example Edge cases
    #   apply_defaults({a: {x: 1}})                # => {a: {x: 1}}
    #   apply_defaults({defaults: {x: 1}, b: {}})  # => {b: {x: 1}}
    #
    def apply_defaults(config={})
      return {} if config.nil? || config.empty?

      # Extract defaults from the configuration
      defaults = config[:defaults]

      # If no valid defaults exist, return config without the :defaults key
      return config.reject { |k, _| k == :defaults } unless defaults.is_a?(Hash)

      # Process each section, applying defaults
      config.each_with_object({}) do |(section, values), result|
        next if section == :defaults   # Skip the :defaults key
        next unless values.is_a?(Hash) # Process only sections that are hashes

        # Apply defaults to each section
        result[section] = deep_merge(defaults, values)
      end
    end

    # Standard deep_merge implementation based on widely used patterns
    # @param original [Hash] Base hash with default values
    # @param other [Hash] Hash with values that override defaults
    # @return [Hash] A new hash containing the merged result
    private def deep_merge(original, other)
      return other.dup if original.nil?
      return original.dup if other.nil?

      other = other.dup
      merger = proc do |_key, v1, v2|
        if v1.is_a?(Hash) && v2.is_a?(Hash)
          v1.merge(v2, &merger)
        elsif v2.nil?
          v1
        else
          v2
        end
      end
      original.merge(other, &merger)
    end


    # Searches for configuration files in predefined locations based on application mode.
    # In CLI mode, it looks in user and system directories. In service mode, it only
    # checks system directories for security and consistency.
    #
    # @param filename [String, nil] Optional configuration filename, defaults to 'config.yaml'
    # @return [Array<String>] List of found configuration file paths in order of precedence
    #
    # @example Finding default config files
    #   find_configs
    #   # => ["/etc/onetime/config.yaml"]
    #
    # @example Finding custom config files
    #   find_configs("database.yaml")
    #   # => ["/etc/onetime/database.yaml", "./etc/database.yaml"]
    def find_configs(filename = nil)
      filename ||= 'config.yaml'
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |f|
        f = File.join File.expand_path(f), filename
        Onetime.ld "Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end
  end

  # A simple map of our config options using our naming conventions
  # to the names that are used by other libraries. This makes it easier
  # for us to have our own consistent naming conventions.
  KEY_MAP = {
    allowed_domains_only: :whitelist_validation,
    allowed_emails: :whitelisted_emails,
    blocked_emails: :blacklisted_emails,
    allowed_domains: :whitelisted_domains,
    blocked_domains: :blacklisted_domains,
    blocked_mx_ip_addresses: :blacklisted_mx_ip_addresses,

    # An example mapping for testing.
    example_internal_key: :example_external_key,
  }


end

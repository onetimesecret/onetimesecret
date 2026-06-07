# lib/onetime/config.rb
#
# frozen_string_literal: true

require_relative 'utils/config_resolver'
require_relative 'utils/enumerables'

module Onetime
  module Config
    extend self

    using Familia::Refinements::TimeLiterals

    unless defined?(SERVICE_PATHS)
      SERVICE_PATHS = %w[/etc/onetime ./etc ./etc/defaults].freeze
      UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc ./etc/defaults].freeze
      DEFAULTS      = {
        'site' => {
          'secret' => nil,
          'secret_options' => {
            'default_ttl' => 7.days,
            # These DEFAULTS are the effective values when the YAML config
            # sets ttl_options to nil (e.g. no TTL_OPTIONS env var). The
            # deep_merge nil-preservation rule means nil in YAML keeps
            # this array intact. The max here (30.days) becomes the global
            # TTL ceiling — override via TTL_OPTIONS env var in production
            # if a lower cap is needed.
            'ttl_options' => [
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
            ],
            'passphrase' => {
              'required' => false,
              'minimum_length' => 4,
              'maximum_length' => 128,
              'enforce_complexity' => false,
            },
            'password_generation' => {
              'default_length' => 12,
              'length_options' => [8, 12, 16, 20, 24, 32],
              'character_sets' => {
                'uppercase' => true,
                'lowercase' => true,
                'numbers' => true,
                'symbols' => false,
                'exclude_ambiguous' => true,
              },
            },
          },
          'interface' => {
            'ui' => { 'enabled' => true },
            'api' => {
              'enabled' => true,
              'guest_routes' => {
                'enabled' => true,
                'conceal' => true,
                'generate' => true,
                'reveal' => true,
                'burn' => true,
                'show' => true,
                'receipt' => true,
              },
            },
          },
          # All keys that we want to explicitly be set to false when enabled
          # is false, should be represented in this hash.
          'authentication' => {
            'enabled' => false,
            'signin' => false,
            'signup' => false,
            'autoverify' => false,
            'allowed_signup_domains' => [],
          },
        },
        'features' => {
          'regions' => { 'enabled' => false },
          'domains' => {
            'enabled' => false,
            # When true, secret creation against an unverified custom
            # share_domain raises a form error. When false (default),
            # creation is allowed regardless of the domain's verification
            # status. Canonical domains are unaffected.
            'require_verified' => false,
          },
          'incoming' => {
            'enabled' => false,
            'memo_max_length' => 50,
            'default_ttl' => 604_800, # 7 days
            'default_passphrase' => nil,
            'recipients' => [],
          },
        },
        'internationalization' => {
          'enabled' => false,
          'default_locale' => 'en',
          'date_format' => 'locale',
          'datetime_format' => 'locale',
        },
        'mail' => {},
        'diagnostics' => {
          'enabled' => false,
        },
        'development' => {
          'enabled' => false,
          'frontend_host' => '',
          'allow_nil_global_secret' => false, # defaults to a secure setting
        },
        'compatibility' => {
          # How the boot process responds when a deprecated config key or
          # env var is detected: 'strict' raises OT::ConfigError, 'warn'
          # logs and continues, 'silent' ignores. See DEPRECATIONS.
          'deprecated_config_mode' => 'strict',
        },
      }

      # Declarative manifest of removed configuration keys.
      #
      # Each entry maps a deprecated config path and/or the env var that
      # used to populate it to a migration message. check_deprecations
      # scans these at boot; compatibility.deprecated_config_mode decides
      # whether a match raises OT::ConfigError ('strict'), logs ('warn'),
      # or is ignored ('silent').
      #
      # Fields:
      #   path:    Array of keys to dig into conf (optional)
      #   env:     Environment variable name (optional)
      #   trigger: Proc that receives the path value; returns true to fire (optional)
      #            When absent, any non-nil value triggers. Use for type-specific checks.
      #   message: User-facing migration guidance
      DEPRECATIONS = [
        {
          path: %w[site interface ui homepage trusted_proxy_depth],
          env: 'UI_HOMEPAGE_TRUSTED_PROXY_DEPTH',
          message: <<~MSG.chomp,
            site.interface.ui.homepage.trusted_proxy_depth is ignored. Configure proxy
            depth globally via site.network.trusted_proxy (TRUSTED_PROXY_ENABLED,
            TRUSTED_PROXY_MODE=depth, TRUSTED_PROXY_DEPTH).
          MSG
        },
        {
          path: %w[site interface ui homepage trusted_ip_header],
          env: 'UI_HOMEPAGE_TRUSTED_IP_HEADER',
          message: <<~MSG.chomp,
            site.interface.ui.homepage.trusted_ip_header is ignored. Configure the
            forwarding header globally via site.network.trusted_proxy.header
            (TRUSTED_PROXY_HEADER).
          MSG
        },
        {
          path: %w[site domains],
          env: nil,
          message: <<~MSG.chomp,
            site.domains is ignored. This config moved to features.domains;
            only the new path is read.
          MSG
        },
        {
          path: %w[site regions],
          env: nil,
          message: <<~MSG.chomp,
            site.regions is ignored. This config moved to features.regions;
            only the new path is read.
          MSG
        },
        {
          path: %w[features regions jurisdictions],
          env: nil,
          # Only trigger on Array (old YAML format), not String (new ENV format)
          trigger: ->(value) { value.is_a?(Array) },
          message: <<~MSG.chomp,
            features.regions.jurisdictions array format is deprecated. Use JURISDICTIONS env var
            (format: EU:eu.example.com,CA:ca.example.com) instead.
          MSG
        },
      ].freeze

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

    # Load a YAML configuration file with layered defaults support.
    #
    # When etc/defaults/config.defaults.yaml exists, it is loaded first as
    # the base layer. The environment-specific file (from +path+) is then
    # deep-merged on top so overrides win. This ensures sections defined
    # only in the defaults file are visible in all environments without
    # manual duplication. See #3322.
    #
    # The YAML layer merge uses preserve_nils: false so that explicit nil
    # in the environment file means "I want nil" (not "keep the default").
    # Nil-preservation is reserved for the in-code DEFAULTS merge in
    # after_load, where nil means "not specified".
    #
    # @param path [String] (optional) path to the environment-specific YAML
    #   file. When nil, layered defaults are applied automatically. When an
    #   explicit path is given, only that file is loaded (no defaults layer).
    # @return [Hash] the parsed, merged YAML data
    #
    def load(path = nil)
      using_default_path = path.nil?
      path ||= self.path
      loading_file = path

      if path.nil? || path.empty?
        raise ArgumentError, 'Config path not set (checked etc/config.yaml and SERVICE_PATHS)'
      end

      unless File.readable?(path)
        raise ArgumentError, "Config not readable: #{path}"
      end

      base_config = if using_default_path
        defaults_file = Onetime::Utils::ConfigResolver.defaults_path('config')
        if defaults_file && defaults_file != path
          loading_file = defaults_file # track for rescue reporting
          load_yaml_with_erb(defaults_file)
        else
          {}
        end
      else
        {}
      end

      loading_file = path
      env_config = load_yaml_with_erb(path)

      if base_config.empty?
        env_config
      else
        Onetime::Utils::Enumerables.deep_merge(base_config, env_config, preserve_nils: false)
      end
    rescue StandardError => ex
      OT.le "Error loading config: #{loading_file}"

      if OT.debug?
        begin
          template_lines = File.read(loading_file).split("\n")
          template_lines.each_with_index do |line, index|
            OT.ld "Line #{index + 1}: #{line}"
          end
        rescue StandardError => debug_ex
          OT.ld "Could not read template for debug output: #{debug_ex.message}"
        end
      end

      OT.le ex.message
      OT.le ex.backtrace.join("\n")
      raise OT::ConfigError.new(ex.message)
    end

    def load_yaml_with_erb(path)
      parsed_template = ERB.new(File.read(path))
      YAML.load(parsed_template.result) || {}
    end
    private :load_yaml_with_erb

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # @param loaded_config [Hash] The loaded, unprocessed configuration hash in raw form
    # @return [Hash] The processed configuration hash with defaults applied and security measures in place
    def after_load(loaded_config)
      # SAFETY MEASURE: Deep Copy Protection
      # Create a deep copy of the configuration to prevent unintended mutations
      # This protects against side effects when multiple components access the same config
      # Without this, modifications to the config in one component could affect others.
      conf = if loaded_config.nil?
        {}
      else
        deep_clone(loaded_config)
      end

      # SAFETY MEASURE: Validation and Default Security Settings
      # Ensure all critical security-related configurations exist
      conf = deep_merge(DEFAULTS, conf) # TODO: We don't need to re-assign `conf`

      raise_concerns(conf)

      # MIGRATION VALIDATION: Detect deprecated configuration keys / env vars
      # and respond per compatibility.deprecated_config_mode.
      # Must run BEFORE jurisdiction parsing so trigger proc sees original type.
      check_deprecations(conf)

      # Parse jurisdictions from string env var format AFTER deprecation check.
      # Format: "EU:eu.example.com,CA:ca.example.com" -> array of hashes
      # The trigger proc above only fires on Array (old YAML format), not String.
      jurisdictions = conf.dig('features', 'regions', 'jurisdictions')
      if jurisdictions.is_a?(String) && !jurisdictions.empty?
        entries                                      = jurisdictions.split(',').map(&:strip).reject(&:empty?)
        conf['features']['regions']['jurisdictions'] = entries.map do |entry|
          identifier, domain = entry.split(':', 2).map(&:strip)
          if identifier.empty? || domain.to_s.empty?
            raise OT::ConfigError, "Invalid JURISDICTIONS format: '#{entry}' (expected ID:domain)"
          end

          {
            'identifier' => identifier,
            'domain' => domain,
            'display_name_i18n_key' => "web.regions.jurisdictions.#{identifier.downcase}.name",
          }
        end
      elsif jurisdictions.is_a?(String) || jurisdictions.nil?
        # Empty string or nil -> empty array
        conf['features']['regions']['jurisdictions'] = []
      end

      # Disable all authentication sub-features when main feature is off for
      # consistency, security, and to prevent unexpected behavior. Ensures clean
      # config state.
      # NOTE: Needs to run after other site.authentication logic
      if conf.dig('site', 'authentication', 'enabled') != true
        conf['site']['authentication'].each_key do |key|
          conf['site']['authentication'][key] = false
        end
      end

      ttl_options = conf.dig('site', 'secret_options', 'ttl_options')
      default_ttl = conf.dig('site', 'secret_options', 'default_ttl')

      # if the ttl_options setting is a string, we want to split it into an
      # array of integers.
      if ttl_options.is_a?(String)
        conf['site']['secret_options']['ttl_options'] = ttl_options.split(/\s+/)
      end
      ttl_options = conf.dig('site', 'secret_options', 'ttl_options')
      if ttl_options.is_a?(Array)
        conf['site']['secret_options']['ttl_options'] = ttl_options.map(&:to_i)
      end

      if default_ttl.is_a?(String)
        conf['site']['secret_options']['default_ttl'] = default_ttl.to_i
      end

      # Process passphrase configuration
      passphrase_config = conf.dig('site', 'secret_options', 'passphrase') || {}

      if passphrase_config['minimum_length'].is_a?(String)
        conf['site']['secret_options']['passphrase']['minimum_length'] = passphrase_config['minimum_length'].to_i
      end

      if passphrase_config['maximum_length'].is_a?(String)
        conf['site']['secret_options']['passphrase']['maximum_length'] = passphrase_config['maximum_length'].to_i
      end

      # Process password generation configuration
      password_gen_config = conf.dig('site', 'secret_options', 'password_generation') || {}

      if password_gen_config['default_length'].is_a?(String)
        conf['site']['secret_options']['password_generation']['default_length'] = password_gen_config['default_length'].to_i
      end

      # Handle length_options as string or array
      length_options = password_gen_config['length_options']
      if length_options.is_a?(String)
        conf['site']['secret_options']['password_generation']['length_options'] = length_options.split(/\s+/).map(&:to_i)
      elsif length_options.is_a?(Array)
        conf['site']['secret_options']['password_generation']['length_options'] = length_options.map(&:to_i)
      end

      # Ensure array jurisdiction entries have display_name_i18n_key
      # (String format already converted to Array above, before check_deprecations)
      jurisdictions = conf.dig('features', 'regions', 'jurisdictions')
      if jurisdictions.is_a?(Array)
        conf['features']['regions']['jurisdictions'] = jurisdictions.map do |j|
          j                            = j.dup if j.frozen?
          j['display_name_i18n_key'] ||= "web.regions.jurisdictions.#{j['identifier'].to_s.downcase}.name"
          j
        end
      end

      # Apply the defaults to sentry backend and frontend configs
      # and set our local config with the merged values.
      diagnostics                                = loaded_config.fetch('diagnostics', {})
      conf['diagnostics']                        = {
        'enabled' => diagnostics['enabled'] || false,
        'sentry' => apply_defaults_to_peers(diagnostics['sentry']),
      }
      conf['diagnostics']['sentry']['backend'] ||= {}

      # Update global diagnostic flag based on config
      backend_dsn  = conf.dig('diagnostics', 'sentry', 'backend', 'dsn')
      frontend_dsn = conf.dig('diagnostics', 'sentry', 'frontend', 'dsn')

      # It's disabled when no DSN is present, regardless of enabled setting
      Onetime.d9s_enabled = !!(conf.dig('diagnostics', 'enabled') && (backend_dsn || frontend_dsn))

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
      #
      # Skip freezing in test mode to allow config modifications for test isolation.
      # Tests may need to modify config values without triggering FrozenError.
      # See also: boot.rb line 133 which guards the raw_conf freeze.
      deep_freeze(conf) unless OT.testing?
      conf
    end

    def raise_concerns(conf)
      # SAFETY MEASURE: Critical Secret Validation
      # Handle potential nil global secret
      # The global secret is critical for encrypting/decrypting secrets
      # Running without a global secret is only permitted in exceptional cases
      # Enforce development-mode constraint: allow_nil_global_secret is
      # only effective when development.enabled is true. Normalize it here
      # before the config is frozen so runtime code can read it directly.
      if conf.dig('development', 'allow_nil_global_secret') && !conf.dig('development', 'enabled')
        OT.le 'CONFIG WARNING: development.allow_nil_global_secret=true ignored because development.enabled is false'
        conf['development']['allow_nil_global_secret'] = false
      end

      allow_nil     = conf.dig('development', 'allow_nil_global_secret') || false
      global_secret = conf.dig('site', 'secret') || nil
      global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

      if global_secret.nil?
        unless allow_nil
          # Fast fail when global secret is nil and not explicitly allowed
          # This is a critical security check that prevents running without encryption
          raise OT::ConfigError, 'Global secret cannot be nil - set SECRET env var or site.secret in config'
        end

        # SAFETY MEASURE: Security Warnings for Dangerous Configurations
        # Security warning when proceeding with nil global secret
        # These warnings are prominently displayed to ensure administrators
        # understand the security implications of their configuration
        OT.li '!' * 50
        OT.li 'SECURITY WARNING: Running with nil global secret!'
        OT.li 'This configuration presents serious security risks:'
        OT.li '- Secret encryption will be compromised'
        OT.li '- Data cannot be properly protected'
        OT.li '- Only use during recovery or transition periods'
        OT.li 'Set valid SECRET env var or site.secret in config ASAP'
        OT.li '!' * 50
      end

      unless conf['mail'].key?('truemail')
        raise OT::ConfigError, 'No TrueMail config found'
      end
    end

    # Detects deprecated configuration keys and environment variables.
    #
    # Scans the DEPRECATIONS manifest. A deprecation is considered present
    # when its config path resolves to a non-nil value, or its env var is
    # set to a non-empty value. The response is governed by
    # compatibility.deprecated_config_mode:
    #
    #   strict (default) - raise OT::ConfigError, refusing to boot
    #   warn             - log each migration message and continue
    #   silent           - ignore
    #
    # An unrecognized policy value is treated as strict.
    #
    # @param conf [Hash] The merged configuration
    # @return [void]
    # @raise [OT::ConfigError] When a deprecated key is found under strict policy
    def check_deprecations(conf)
      detected = DEPRECATIONS.select do |dep|
        env_set = !!(dep[:env] && !ENV[dep[:env]].to_s.empty?)

        # Check path, optionally with a trigger proc for type-specific detection
        path_value = dep[:path] && conf.dig(*dep[:path])
        path_set   = if dep[:trigger] && path_value
          dep[:trigger].call(path_value)
        else
          !path_value.nil?
        end

        env_set || path_set
      end
      return if detected.empty?

      policy   = (conf.dig('compatibility', 'deprecated_config_mode') || 'strict').to_s
      messages = detected.map { |dep| dep[:message] }
      return if policy == 'silent'

      if policy == 'warn'
        messages.each { |msg| OT.le "CONFIG DEPRECATION: #{msg}" }
        return
      end

      raise OT::ConfigError,
        "Deprecated configuration detected:\n  - #{messages.join("\n  - ")}\n\n" \
        "Set compatibility.deprecated_config_mode (DEPRECATED_CONFIG_MODE) to 'warn' " \
        'to downgrade this to a logged warning.'
    end

    def dirname
      @dirname ||= File.dirname(path)
    end

    def path
      @path ||= Onetime::Utils::ConfigResolver.resolve('config') || find_configs.first
    end

    def mapped_key(key)
      # `key` is a string. Returns a string.
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
      # Previously used Marshal here. But in Ruby 3.1 it died cryptically with
      # a singleton error. It seems like it's related to gibbler but since we
      # know we only expect a regular hash here without any methods, procs
      # etc, we use YAML instead to accomplish the same thing (JSON is
      # another option but it turns all the symbol keys into strings).
      YAML.load(YAML.dump(config_hash))
    rescue TypeError => ex
      raise OT::Problem, "[deep_clone] #{ex.message}"
    end

    # Applies default values to its config level peers
    #
    # @param config [Hash] Configuration with top-level section keys, including a 'defaults' key
    # @return [Hash] Configuration with defaults applied to each section, with 'defaults' removed
    #
    # This method extracts defaults from the 'defaults' key and applies them to each section:
    # - Section values override defaults (except nil values, which use defaults)
    # - The 'defaults' section is removed from the result
    # - Only Hash-type sections receive defaults
    #
    # @example Basic usage
    #   config = {
    #     'defaults' => { 'timeout' => 5, 'enabled' => true },
    #     'api' => { 'timeout' => 10 },
    #     'web' => { 'theme' => 'dark' }
    #   }
    #   apply_defaults_to_peers(config)
    #   # => { 'api' => { 'timeout' => 10, 'enabled' => true },
    #   #      'web' => { 'theme' => 'dark', 'timeout' => 5, 'enabled' => true } }
    #
    # @example Edge cases
    #   apply_defaults_to_peers({'a' => {'x' => 1}})                # => {'a' => {'x' => 1}}
    #   apply_defaults_to_peers({'defaults' => {'x' => 1}, 'b' => {}})  # => {'b' => {'x' => 1}}
    #
    def apply_defaults_to_peers(config = {})
      return {} if config.nil? || config.empty?

      # Extract defaults from the configuration
      defaults = config['defaults']

      # If no valid defaults exist, return config without the 'defaults' key
      return config.except('defaults') unless defaults.is_a?(Hash)

      # Process each section, applying defaults
      config.each_with_object({}) do |(section, values), result|
        next if section == 'defaults'   # Skip the 'defaults' key
        next unless values.is_a?(Hash) # Process only sections that are hashes

        # Apply defaults to each section
        result[section] = deep_merge(defaults, values)
      end
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
      paths      = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |path|
        f = File.join File.expand_path(path), filename
        Onetime.ld "[init] Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end

    # Makes a deep copy of OT.conf, then merges the system settings data, and
    # replaces OT.config with the merged data.
    def apply_config(other)
      new_config = deep_merge(OT.conf, other)
      OT.replace_config! new_config
    end

    # Deep merge with nil-preservation semantics.
    #
    # When YAML config resolves a key to nil (e.g. `ttl_options: <%= nil %>`),
    # the DEFAULTS value is preserved — nil means "not specified", not "empty".
    # This is the v2.nil? branch below: if the loaded config has nil for a key,
    # the original (DEFAULTS) value wins.
    #
    # Consequence: DEFAULTS.ttl_options.max determines the effective TTL ceiling
    # unless the deployment explicitly sets TTL_OPTIONS. An empty string would
    # NOT trigger this preservation (it's truthy), so `ttl_options: ""` would
    # replace the array with "" — use nil, not empty string, to inherit defaults.
    #
    # @param original [Hash] Base hash with default values
    # @param other [Hash] Hash with values that override defaults
    # @return [Hash] A new hash containing the merged result
    def deep_merge(original, other)
      return deep_clone(other) if original.nil?
      return deep_clone(original) if other.nil?

      original_clone = deep_clone(original)
      other_clone    = deep_clone(other)
      merger         = proc do |_key, v1, v2|
        if v1.is_a?(Hash) && v2.is_a?(Hash)
          v1.merge(v2, &merger)
        elsif v2.nil?
          v1 # nil in loaded config = "not specified" → keep default
        else
          v2
        end
      end
      original_clone.merge(other_clone, &merger)
    end
  end

  # A simple map of our config options using our naming conventions
  # to the names that are used by other libraries. This makes it easier
  # for us to have our own consistent naming conventions.
  unless defined?(KEY_MAP)
    KEY_MAP = {
      # NOTE: validation_type_for is NOT mapped because it's the correct setter name
      # in Truemail. The getter is validation_type_by_domain (asymmetric API).
      'allowed_domains_only' => 'whitelist_validation',
      'allowed_emails' => 'whitelisted_emails',
      'blocked_emails' => 'blacklisted_emails',
      'allowed_domains' => 'whitelisted_domains',
      'blocked_domains' => 'blacklisted_domains',
      'blocked_mx_ip_addresses' => 'blacklisted_mx_ip_addresses',

      # An example mapping for testing.
      'example_internal_key' => 'example_external_key',
    }
  end
end

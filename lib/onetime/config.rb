# lib/onetime/config.rb

require 'json'
require 'json_schemer'
require 'yaml'

require 'onetime/refinements/hash_refinements'

module Onetime
  module Config
    extend self

    using IndifferentHashAccess

    unless defined?(SERVICE_PATHS)
      SERVICE_PATHS = %w[/etc/onetime ./etc].freeze
      UTILITY_PATHS = %w[~/.onetime /etc/onetime ./etc].freeze
      DEFAULTS = {
        site: {
          secret: nil,
          api: { enabled: true },
          authentication: {
            enabled: false,
            colonels: [],
          },
          authenticity: {
            enabled: false,
            type: nil,
            secret_key: nil,
          },
          middleware: {
            static_files: true,
            utf8_sanitizer: true,
          },
        },
        storage: {
          db: {
            connection: {
              url: 'redis://localhost:6379',
            },
            database_mapping: nil,
          },
        },
        mail: {
          connection: {
            mode: 'smtp',
            from: "noreply@example.com",
            fromname: "OneTimeSecret",
          },
        },
        logging: {
          http_requests: true,
        },
        i18n: {
          enabled: false,
          default_locale: 'en',
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

    def load
      # Load schema before loading configuration
      schema = _load_json_schema

      # Normalize environment variables prior to loading the YAML config
      before_load

      # Loads the configuration and renders all value templates (ERB)
      raw_conf = _load_static_configuration

      # Validate against schema and apply defaults
      validate_with_schema(raw_conf, schema)

      # SAFETY MEASURE: Freeze this shared config so that we are sure to
      # have an unmodified version straight from the YAML file.
      OT::Utils.deep_freeze(raw_conf)

      # Normalize the configuration and make it available to the rest
      # of the initializers (via OT.conf).
      after_load(raw_conf)
    end

    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    def before_load
      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      ENV['REGIONS_ENABLED'] = ENV.values_at('REGIONS_ENABLED', 'REGIONS_ENABLE').compact.first || 'false'
    end

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # @param incoming_config [Hash] The loaded, unprocessed configuration hash in raw form
    # @return [Hash] The processed configuration hash with defaults applied and security measures in place
    def after_load(incoming_config)

      # SAFETY MEASURE: Deep Copy Protection
      # Create a deep copy of the configuration to prevent unintended mutations
      # This protects against side effects when multiple components access the same config
      # Without this, modifications to the config in one component could affect others.
      copied_conf = OT::Utils.deep_clone(incoming_config)
      conf = OT::Utils.deep_merge(DEFAULTS, copied_conf)

      # These are checks for things that we cannot continue booting without. We
      # don't need to exit immediately -- for example, running a console session
      # or in tests or running in development mode. But we should not be
      # continuing in a production ready state if any of these checks fail.
      # raise_concerns(conf)

      #
      # SEE code past end of file for the inline logic we used here to read
      # and set both OT.conf and OT.d9s_enabled etc flags in an unclear way.
      #

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
      OT::Utils.deep_freeze(conf)
    end

    def validate_with_schema(conf, schema)

      # Create schema validator with defaults insertion enabled
      schemer = JSONSchemer.schema(
        schema,
        meta_schema: 'https://json-schema.org/draft/2020-12/schema',
        insert_property_defaults: true,

        #before_property_validation: ->(data, property, property_schema, _parent) { data }
        #after_property_validation: ->(data) { data }

        format: true,
      )

      # Validate and collect errors
      errors = schemer.validate(conf).to_a
      return if errors.empty?

      # Format error messages
      error_messages = errors.map do |err|
        "#{err['error']} at #{err['pointer']}" # e.g. /mail/connection/fromname
      end.join("\n")

      conf_safe = OT::Utils.type_structure(conf)
      conf_pretty = JSON.pretty_generate(conf_safe)
      raise OT::ConfigError, "Configuration validation failed:\n#{error_messages}\n#{conf_pretty}"
    end

    # Access conf here but not Onetime.conf or any other global flag etc.
    def raise_concerns(conf)

      # SAFETY MEASURE: Critical Secret Validation
      # Handle potential nil global secret
      # The global secret is critical for encrypting/decrypting secrets
      # Running without a global secret is only permitted in exceptional cases
      allow_nil = conf.dig(:experimental, :allow_nil_global_secret) || false
      global_secret = conf[:site].fetch(:secret, nil)
      global_secret = nil if global_secret.to_s.strip == 'CHANGEME'

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

      unless conf[:mail].key?(:validation)
        raise OT::ConfigError, "No mail validation config found (TrueMail)"
        # OT.le "TEMPORARY WARNING: No TrueMail config found"
      end
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

    # Applies default values to its config level peers
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
    #   apply_defaults_to_peers(config)
    #   # => { api: { timeout: 10, enabled: true },
    #   #      web: { theme: 'dark', timeout: 5, enabled: true } }
    #
    # @example Edge cases
    #   apply_defaults_to_peers({a: {x: 1}})                # => {a: {x: 1}}
    #   apply_defaults_to_peers({defaults: {x: 1}, b: {}})  # => {b: {x: 1}}
    #
    def apply_defaults_to_peers(config={})
      return {} if config.nil? || config.empty?

      # Extract defaults from the configuration
      defaults = config[:defaults]

      # If no valid defaults exist, return config without the :defaults key
      return config.except(:defaults) unless defaults.is_a?(Hash)

      # Process each section, applying defaults
      config.each_with_object({}) do |(section, values), result|
        next if section == :defaults   # Skip the :defaults key
        next unless values.is_a?(Hash) # Process only sections that are hashes

        # Apply defaults to each section
        result[section] = OT::Utils.deep_merge(defaults, values)
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
      paths = Onetime.mode?(:cli) ? UTILITY_PATHS : SERVICE_PATHS
      paths.collect do |path|
        f = File.join File.expand_path(path), filename
        Onetime.ld "Looking for #{f}"
        f if File.exist?(f)
      end.compact
    end

    # Makes a deep copy of OT.conf, then merges the system settings data, and
    # replaces OT.config with the merged data.
    def apply_config(other)
      new_config = OT::Utils.deep_merge(OT.conf, other)
      OT.replace_config! new_config
    end

    private

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def _load_static_configuration(path=nil)
      path ||= self.path

      parsed_template = _file_read(path)

      _yaml_load(parsed_template)

    rescue OT::ConfigError => e
      # DEBUGGING: Allow the contents of the parsed template to be logged.
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
      OT.ld e.backtrace.join("\n")
      raise e
    end

    def _file_read(path)
      raise ArgumentError, "Bad path (#{path})" unless File.readable?(path)

      ERB.new(File.read(path)) # returns the parsed template object

    rescue Errno::ENOENT => e
      OT.le "Config file not found: #{path}"
      raise OT::ConfigError, "Configuration file not found: #{path}"
    end

    def _yaml_load(parsed)
      YAML.load(parsed.result) # use YAML.safe_load(parsed.result)
    rescue Psych::SyntaxError => e
      OT.le "Error parsing YAML: #{e.message}"
      raise OT::ConfigError, "Error parsing YAML: #{e.message}"
    end

    def _load_json_schema
      path = File.join(dirname, 'schemas', 'static-config.json')
      raise OT::ConfigError, "Schema file not found: #{path}" unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      raise OT::ConfigError, "Invalid JSON schema: #{e.message}"
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


__END__

```ruby
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
conf[:site][:authentication][:colonels] = (auth_colonels + root_colonels).compact.uniq

# Clear colonels and set to false if authentication is disabled
unless conf.dig(:site, :authentication, :enabled)
  conf[:site][:authentication][:colonels] = false
end

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
  sentry: apply_defaults_to_peers(diagnostics[:sentry]),
}
conf[:diagnostics][:sentry][:backend] ||= {}

# Update global diagnostic flag based on config
backend_dsn = conf.dig(:diagnostics, :sentry, :backend, :dsn)
frontend_dsn = conf.dig(:diagnostics, :sentry, :frontend, :dsn)

# It's disabled when no DSN is present, regardless of enabled setting
Onetime.d9s_enabled = !!(conf.dig(:diagnostics, :enabled) && (backend_dsn || frontend_dsn))
```

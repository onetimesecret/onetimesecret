# lib/onetime/configurator.rb
#
# frozen_string_literal: true

require 'json'
require 'erb'
require 'yaml'
require 'pathname'

require_relative 'errors'
require_relative 'configurator/environment_context'
require_relative 'configurator/load'
require_relative 'configurator/utils'

module Onetime
  # Configuration loader using two-stage validation pattern
  #
  # 1. Schema validation (declarative) - structure + defaults
  # 2. Business processing (imperative) - capabilities, auth, etc.
  # 3. Re-validation (declarative) - ensures processing didn't break schema
  #
  # Pipeline: Read → ERB → YAML → Validate → Defaults → Process → Revalidate → Freeze
  #
  # Schema validation is optional: if the schema file doesn't exist (e.g., schemas
  # not yet generated), validation steps pass through with a debug log.
  class Configurator
    GENERATED_SCHEMA_PATH = File.join(
      defined?(Onetime::HOME) ? Onetime::HOME : Pathname(__dir__).parent.freeze,
      'generated',
      'schemas',
      'config',
      'static.schema.json',
    ).freeze

    attr_accessor :config_path, :schema_path
    attr_reader :configuration,
      :strict,
      :template_str,
      :rendered_template,
      :parsed_yaml

    # @param strict [Boolean] When true (default), schema validation errors raise.
    #   When false, validation errors are logged as warnings and the pipeline continues.
    #   Use strict: false during boot to tolerate schema drift; strict: true for
    #   explicit validation (e.g., `bin/ots config validate`).
    def initialize(config_path: nil, schema_path: nil, strict: true)
      @config_path = config_path || OT::Config.path
      @schema_path = schema_path || GENERATED_SCHEMA_PATH
      @strict      = strict
    end

    # Loads and validates the configuration through the 8-step pipeline.
    #
    # @return [Configurator] Self, with fully loaded and validated configuration
    # @raise [OT::ConfigValidationError] If configuration fails schema validation
    # @raise [OT::ConfigError] If configuration loading encounters an error
    def load!
      @configuration = config_path
        .then { |path| read_template(path) }
        .then { |template| render_erb(template) }
        .then { |content| parse_yaml(content) }
        .then { |config| validate_structure(config) }
        .then { |config| apply_defaults(config) }
        .then { |config| process(config) }
        .then { |config| validate_processed(config) }
        .then { |config| freeze_config(config) }

      self
    rescue OT::ConfigValidationError
      raise
    rescue OT::ConfigError => ex
      OT.ld ex.backtrace&.join("\n")
      raise
    end

    # Factory method
    def self.load!(**)
      new(**).load!
    end

    private

    # Step 1: Read the raw template file
    def read_template(path)
      OT.ld "[configurator] Reading template: #{path}"
      @template_str = Configurator::Load.file_read(path)
    end

    # Step 2: Render ERB with normalized environment context
    def render_erb(template)
      OT.ld "[configurator] Rendering ERB (#{template.size} bytes)"
      context            = Configurator::EnvironmentContext.template_binding
      erb                = ERB.new(template)
      @rendered_template = erb.result(context)
    end

    # Step 3: Parse YAML content
    def parse_yaml(content)
      OT.ld "[configurator] Parsing YAML (#{content.size} bytes)"
      @parsed_yaml = Configurator::Load.yaml_load(content)
    end

    # Step 4: First schema validation — structural integrity + insert defaults
    def validate_structure(config)
      unless schema_available?
        OT.ld '[configurator] Schema not available, skipping structure validation'
        return config
      end
      OT.ld "[configurator] Validating structure (#{config.size} sections)"
      Configurator::Utils.validate_against_schema(config, schema, apply_defaults: true)
    rescue OT::ConfigValidationError => ex
      raise if strict

      OT.le "[configurator] Schema validation warning (structure): #{ex.messages.size} issues"
      ex.messages.each { |msg| OT.ld "  - #{msg}" }
      config
    end

    # Step 5: Merge hardcoded defaults from Config::DEFAULTS
    def apply_defaults(config)
      OT.ld '[configurator] Applying defaults'
      OT::Config.deep_merge(OT::Config::DEFAULTS, config)
    end

    # Step 6: Business logic processing (extracted from Config.after_load)
    def process(config)
      OT.ld '[configurator] Processing config'

      # Deep clone before mutation to prevent side effects on prior pipeline state
      config = OT::Config.deep_clone(config)

      # Validation checks (fail-fast)
      OT::Config.raise_concerns(config)

      # Migration warnings
      OT::Config.validate_domains_migration(config)
      OT::Config.validate_regions_migration(config)

      # Disable auth sub-features when main feature is off
      if config.dig('site', 'authentication', 'enabled') != true
        config['site']['authentication'].each_key do |key|
          config['site']['authentication'][key] = false
        end
      end

      coerce_secret_option_types(config)
      process_diagnostics(config)

      config
    end

    # Coerce string values to integers for secret_options sub-keys.
    # YAML sometimes delivers numeric values as strings depending on
    # quoting or ERB output.
    def coerce_secret_option_types(config) # rubocop:disable Metrics/PerceivedComplexity
      secret_opts = config.dig('site', 'secret_options') || {}

      # TTL options
      ttl_options                = secret_opts['ttl_options']
      secret_opts['ttl_options'] = ttl_options.split(/\s+/) if ttl_options.is_a?(String)
      ttl_options                = secret_opts['ttl_options']
      secret_opts['ttl_options'] = ttl_options.map(&:to_i) if ttl_options.is_a?(Array)

      secret_opts['default_ttl'] = secret_opts['default_ttl'].to_i if secret_opts['default_ttl'].is_a?(String)

      # Passphrase
      passphrase                   = secret_opts['passphrase'] || {}
      passphrase['minimum_length'] = passphrase['minimum_length'].to_i if passphrase['minimum_length'].is_a?(String)
      passphrase['maximum_length'] = passphrase['maximum_length'].to_i if passphrase['maximum_length'].is_a?(String)

      # Password generation
      pw_gen                   = secret_opts['password_generation'] || {}
      pw_gen['default_length'] = pw_gen['default_length'].to_i if pw_gen['default_length'].is_a?(String)
      length_options           = pw_gen['length_options']
      if length_options.is_a?(String)
        pw_gen['length_options'] = length_options.split(/\s+/).map(&:to_i)
      elsif length_options.is_a?(Array)
        pw_gen['length_options'] = length_options.map(&:to_i)
      end
    end

    # Apply defaults to sentry backend/frontend configs and set diagnostics flag
    def process_diagnostics(config)
      diagnostics                                  = @parsed_yaml&.fetch('diagnostics', {}) || {}
      config['diagnostics']                        = {
        'enabled' => diagnostics['enabled'] || false,
        'sentry' => OT::Config.apply_defaults_to_peers(diagnostics['sentry']),
      }
      config['diagnostics']['sentry']['backend'] ||= {}

      backend_dsn         = config.dig('diagnostics', 'sentry', 'backend', 'dsn')
      frontend_dsn        = config.dig('diagnostics', 'sentry', 'frontend', 'dsn')
      Onetime.d9s_enabled = !!(config.dig('diagnostics', 'enabled') && (backend_dsn || frontend_dsn))
    end

    # Step 7: Second schema validation — ensures processing didn't break schema
    def validate_processed(config)
      unless schema_available?
        OT.ld '[configurator] Schema not available, skipping processed validation'
        return config
      end
      OT.ld "[configurator] Validating processed config (#{config.size} sections)"
      Configurator::Utils.validate_against_schema(config, schema, apply_defaults: false)
    rescue OT::ConfigValidationError => ex
      raise if strict

      OT.le "[configurator] Schema validation warning (processed): #{ex.messages.size} issues"
      ex.messages.each { |msg| OT.ld "  - #{msg}" }
      config
    end

    # Step 8: Deep freeze for immutability
    def freeze_config(config)
      OT.ld "[configurator] Deep freezing (#{config.size} sections)"
      OT::Config.deep_freeze(config)
    end

    def schema_available?
      schema_path && File.exist?(schema_path)
    end

    def schema
      @schema ||= Configurator::Load.json_load_file(schema_path)
    end
  end
end

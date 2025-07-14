# lib/onetime/configurator.rb

require 'json'
require 'erb'
require 'yaml'
require 'pathname'
require 'xdg'

require_relative 'errors'
require_relative 'configurator/environment_context'
require_relative 'configurator/load'
require_relative 'configurator/utils'

require_relative 'refinements/then_with_diff'

module Onetime
  # Configuration loader using two-stage validation pattern
  #
  # 1. Schema validation (declarative) - structure + defaults
  # 2. Business processing (imperative) - capabilities, auth, etc.
  # 3. Re-validation (declarative) - ensures processing didn't break schema
  #
  # Pipeline: ENV normalize → Read → ERB → YAML → Validate → Process → Revalidate → Freeze
  class Configurator
    using Onetime::ThenWithDiff

    # TODO: Add resolve_and_validate_home in onetime/constants.rb and maybe
    # rename to onetime/setup.rb.
    @home = defined?(Onetime::HOME) ? Onetime::HOME : Pathname(__dir__).parent.parent.freeze

    @xdg = XDG::Environment.new

    # Use an override config file basename if one is set. The basename is part
    # of the filename to the left of the .yaml extension. The canonical example
    # is the 'config' in etc/config.yaml.
    @config_file_basename = ENV.fetch('ONETIME_CONFIG_FILE_BASENAME', 'config').freeze

    # This lets local project settings override user settings, which
    # override system defaults. It's the standard precedence with
    # the addition of a test directory.
    @paths      = [
      File.join(Dir.pwd, 'etc'), # 1. current working directory
      File.join(Dir.pwd, 'etc', 'schemas'), # 2. current working directory
      File.join(@home, 'etc'), # 3. onetimesecret/etc
      File.join(@xdg.config_home, 'onetime'), # 4. ~/.config/onetime
      File.join(File::SEPARATOR, 'etc', 'onetime'), # 5. /etc/onetime
      File.join(@home, 'spec'), # 6. ./spec
    ].uniq.freeze
    @extensions = ['.yml', '.yaml', '.json', '.json5', ''].freeze

    attr_accessor :config_path, :schema_path

    attr_reader :schema, :file_basename,
      # Ordered states the configuration is at during the load pipeline
      :template_str, :template_instance, :rendered_template, :parsed_yaml,
      :validated_with_defaults, :processed, :validated, :validated_and_frozen

    def initialize(config_path: nil, schema_path: nil, basename: nil)
      @file_basename = basename || self.class.config_file_basename
      @config_path   = config_path || self.class.find_config(file_basename)
      @schema_path   = schema_path || self.class.find_config("#{file_basename}.schema")
    end

    # Typically called via `OT::Configurator.load!`. The block is a processing
    # hook that runs after initial validation but before final freeze, allowing
    # config transformations (e.g., backwards compatibility, auth settings).
    #
    # Using a combination of then and then_with_diff which tracks the changes to
    # the configuration at each step in this load pipeline.
    def load!(&)
      # We validate before returning the config so that we're not inadvertently
      # sending back configuration of unknown provenance. This is Stage 1 of
      # our two-stage validation process. In addition to confirming the
      # correctness, this validation also applies default values.
      @configuration = config_path
        # https://docs.ruby-lang.org/en/3.4/Kernel.html#method-i-then
        # https://docs.ruby-lang.org/en/3.4/Enumerable.html#method-i-find
        # Use detect as a circuit breaker (it's an alias for find)
        #     1.then.detect(&:odd?)            # => 1
        # Does not meet condition, drop value
        #     2.then.detect(&:odd?)            # => nil
        .then { |path| read_template_file(path) }
        .then { |template| render_erb_template(template) }
        .then { |yaml_content| parse_yaml(yaml_content) }
        .then { |config| resolve_and_load_schema(config) }
        .then_with_diff('initial') { |config| validate_with_defaults(config) }
        .then_with_diff('processed') { |config| run_processing_hook(config, &) }
        .then_with_diff('validated') { |config| validate(config) }
        .then_with_diff('freezed') { |config| deep_freeze(config) }

      self
    rescue OT::ConfigValidationError
      # Re-raise without debug logging
      raise
    rescue OT::ConfigError => ex
      log_error_with_debug_content(ex)
      raise # re-raise the same error
    rescue StandardError => ex
      log_error_with_debug_content(ex)
      raise OT::ConfigError, "Unhandled error: #{ex.message}"
    end

    # The accessor creates a new config hash every time and returns it frozen
    def configuration
      OT::Utils.deep_clone(@configuration).freeze
    end

    def read_template_file(path)
      OT.ld("[config] Reading template file: #{path}")
      @template_str = OT::Configurator::Load.file_read(path)
    end

    # We create the environment context with the normalized ENV vars
    # and make it available to ERB during the rendering process. It's
    # all self-contained and does not rely on external dependencies or
    # affect the global ENV.
    def render_erb_template(template)
      OT.ld("[config] Rendering ERB template (#{template.size} bytes)")
      context            = Onetime::Configurator::EnvironmentContext.template_binding
      @template_instance = ERB.new(template)
      @rendered_template = @template_instance.result(context)
    end

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def parse_yaml(content)
      OT.ld("[config] Parsing YAML content (#{content.size} bytes)")
      @parsed_yaml = OT::Configurator::Load.yaml_load(content)
    end

    # Configuration processing can introduce new failure modes so we validate
    # both when the config is loaded initially and after processing. This
    # allows us to fail fast with clear error messages.
    # First validation: Schema validation before processing.
    # Ensures structural integrity, applies defaults.
    def validate_with_defaults(config)
      OT.ld("[config] Validating w/ defaults (#{config.size} sections)")
      @validated_with_defaults = _validate(config, apply_defaults: true)
    end

    # Processing hook - runs after initial validation but before final freeze.
    # This is where imperative config transformations happen (backwards
    # compatibility, derived values, etc). The config is mutable here.
    #
    # Within this hook:
    # - etc/init.d scripts: Per-section setup (e.g., site.rb for 'site' config)
    # - Can modify config, register routes, set feature flags
    #
    # After config is frozen:
    # - onetime/services/system: System-wide services (Redis, i18n, emailer, etc.)
    # - Cannot modify config, only read it to configure services
    #
    # @return [Hash] The processed configuration
    def run_processing_hook(config, &)
      OT.ld("[config] Run init hook (has block: #{block_given?})")
      yield(config) if block_given?
      @processed = config # return the config back to the pipeline
    end

    def validate(config)
      OT.ld("[config] Validating w/o defaults (#{config.size} sections)")
      @validated = _validate(config, apply_defaults: false)
    end

    # This is a convenience wrapper for the load! pipeline. It conforms to the
    # expected inputs and outputs for the pipeline rather than rely on external
    # methods.
    def deep_freeze(config)
      OT.ld("[config] Deep freezing (#{config.size} sections; already frozen: #{config.frozen?})")
      @validated_and_frozen = OT::Utils.deep_freeze(config)
    end

    def log_error_with_debug_content(err)
      # NOTE: the following three debug outputs are very handy for diagnosing
      # config problems but also very noisy. We don't have a way of setting
      # the verbosity level so you'll need to uncomment when needed.
      #
      # OT.ld <<~DEBUG
      #   [config] Loaded `#{parsed_yaml.class}`) from template:
      #     #{template_str.to_s[0..500]}`
      # DEBUG
      #
      # This helps identify issues with template rendering and provides
      # context for the error, making it easier to diagnose config
      # problems, especially when the error involves environment vars.
      # if OT.debug? && rendered_template
      #   template_lines = rendered_template.split("\n")
      #   template_lines.each_with_index do |line, index|
      #     OT.ld "Line #{index + 1}: #{line}"
      #   end
      # end
      #
      # if parsed_yaml
      #   loggable_config = OT::Utils.type_structure(parsed_yaml)
      #   OT.ld "[config] Parsed: #{loggable_config}"
      # end

      OT.ld err.backtrace.join("\n")
    end

    def resolve_and_load_schema(config)
      @schema_path = _resolve_schema(config)

      OT.ld "[config] Loading schema from #{schema_path.inspect}"
      @schema = OT::Configurator::Load.yaml_load_file(schema_path)

      # Remove $schema from config
      config.reject { |k| k.to_s == '$schema' }
    end

    def load_with_impunity!(&)
      config = config_path
        .then { |path| read_template_file(path) }
        .then { |template| render_erb_template(template) }
        .then { |yaml_content| parse_yaml(yaml_content) }
      OT::Utils.deep_freeze(config)
    end

    private

    def _validate(config, **)
      unless config.is_a?(Hash) && schema.is_a?(Hash)
        raise ArgumentError, "Cannot validate #{config.class} with #{schema.class}"
      end

      loggable_config = OT::Utils.type_structure(config)
      OT.ld "[config] Validating #{loggable_config.size} #{schema.size}"
      OT::Configurator::Utils.validate_with_schema(config, schema, **)
    end

    def _resolve_schema(config)
      # Extract schema reference from parsed config
      schema_ref = config['$schema'] || config[:$schema]

      # No need to autodetect schema if it's already set
      if schema_ref && schema_ref != schema_path
        OT.ld("[config] Found $schema ref: #{schema_ref}")

        # Try Load module's resolution first (direct + relative paths)
        resolved_path = Load.resolve_schema_path(schema_ref, config_path)

        # Fall back to basename search in predefined paths if not found
        if resolved_path.nil?
          basename      = File.basename(schema_ref, File.extname(schema_ref))
          resolved_path = self.class.find_config(basename) || schema_ref
        end

        @schema_path = resolved_path
      end

      @schema_path
    end

    class << self
      attr_reader :xdg, :paths, :extensions, :init_scripts_dir, :config_file_basename

      # Instantiates a new configuration object, loads it, and it returns itself
      def load!(&) = new.load!(&)

      def load_with_impunity!(&)
        new.load_with_impunity!(&)
      end

      def find_configs(basename = nil)
        basename ||= config_file_basename
        paths.flat_map do |path|
          extensions.filter_map do |ext|
            file = File.join(path, "#{basename}#{ext}")
            file if File.exist?(file)
          end
        end
      end

      def find_config(...)
        find_configs(...).first
      end
    end
  end
end

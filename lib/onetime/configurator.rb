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

require 'onetime/refinements/hash_refinements'

module Onetime
  # Configuration loader using two-stage validation pattern:
  # 1. Schema validation (declarative) - structure + defaults
  # 2. Business processing (imperative) - compatibility, auth, etc.
  # 3. Re-validation (declarative) - ensures processing didn't break schema
  #
  # Pipeline: ENV normalize → Read → ERB → YAML → Validate → Process → Revalidate → Freeze
  class Configurator
    using IndifferentHashAccess
    using ThenWithDiff

    @xdg = XDG::Environment.new

    # This lets local project settings override user settings, which
    # override system defaults. It's the standard precedence.
    @paths      = [
      File.join(Dir.pwd, 'etc'), # 1. current working directory
      File.join(Onetime::HOME, 'etc'), # 2. onetimesecret/etc
      File.join(@xdg.config_home, 'onetime'), # 3. ~/.config/onetime
      File.join(File::SEPARATOR, 'etc', 'onetime'), # 4. /etc/onetime
    ].uniq.freeze
    @extensions = ['.yml', '.yaml', '.json', '.json5', ''].freeze

    attr_accessor :config_path, :schema_path
    attr_reader :schema, :parsed_yaml, :config_template_str, :processed_config

    def initialize(config_path: nil, schema_path: nil)
      @config_path = config_path || self.class.find_config('config')
      @schema_path = schema_path || self.class.find_config('config.schema')
    end

    # States:
    attr_reader :unprocessed_config, :validated_config, :schema, :parsed_template

    # Typically called via `OT::Configurator.load!`. The block is a processing
    # hook that runs after initial validation but before final freeze, allowing
    # config transformations (e.g., backwards compatibility, auth settings).
    #
    # Using a combination of then and then_with_diff which tracks the changes to
    # the configuration at each step in this load pipeline.
    def load!(&)
      @schema        = load_schema
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
        .then_with_diff('initial') { |config| validate_with_defaults(config) }
        .then_with_diff('processed') { |config| run_processing_hook(config, &) }
        .then_with_diff('validated') { |config| validate(config) }
        .then_with_diff('freezed') { |config| deep_freeze(config) }

      self
    rescue OT::ConfigError => ex
      log_debug_content(ex)
      raise
    rescue StandardError => ex
      log_debug_content(ex)
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
      @rendered_template = ERB.new(template).result(context)
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
      _validate(config, apply_defaults: true)
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
      config # return the config back to the pipeline
    end

    def validate(config)
      OT.ld("[config] Validating w/o defaults (#{config.size} sections)")
      _validate(config, apply_defaults: false)
    end

    def deep_freeze(config)
      OT.ld("[config] Deep freezing (#{config.size} sections; already frozen: #{config.frozen?})")
      OT::Utils.deep_freeze(config)
    end

    def log_debug_content(err)
      # DEBUGGING: Allow the contents of the parsed template to be logged.
      # This helps identify issues with template rendering and provides
      # context for the error, making it easier to diagnose config
      # problems, especially when the error involves environment vars.
      if OT.debug? && @parsed_template
        template_lines = @parsed_template.result.split("\n")
        template_lines.each_with_index do |line, index|
          OT.ld "Line #{index + 1}: #{line}"
        end
      end

      OT.ld <<~DEBUG
        [config] Loaded `#{@parsed_yaml.class}`) from template:
          #{@template_str.to_s[0..100]}`
      DEBUG

      if unprocessed_config
        loggable_config = OT::Utils.type_structure(unprocessed_config)
        OT.ld "[config] Parsed: #{loggable_config}"
      end

      OT.le err.message
      OT.ld err.backtrace.join("\n")
    end

    def load_schema(path = nil)
      path ||= schema_path
      OT.ld "[config] Loading schema from #{path.inspect}"
      OT::Configurator::Load.yaml_load_file(path)
    end

    private

    def _validate(config, **)
      unless config.is_a?(Hash) && schema.is_a?(Hash)
        raise ArgumentError, 'Invalid configuration format'
      end

      loggable_config = OT::Utils.type_structure(config)
      OT.ld "[config] Validating #{loggable_config.size} #{schema.size}"
      OT::Configurator::Utils.validate_with_schema(config, schema, **)
    end

    class << self
      attr_reader :xdg, :paths, :extensions, :init_scripts_dir

      # Instantiates a new configuration object, loads it, and it returns itself
      def load!(&) = new.load!(&)

      def find_configs(basename = 'config')
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

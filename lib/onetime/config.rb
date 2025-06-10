# lib/onetime/config.rb

require 'json'
require 'erb'
require 'yaml'
require 'pathname'
require 'xdg'

require_relative 'errors'
require_relative 'config/load'
require_relative 'config/utils'

require 'onetime/refinements/hash_refinements'

module Onetime

  # Configuration loader using two-stage validation pattern:
  # 1. Schema validation (declarative) - structure + defaults
  # 2. Business processing (imperative) - compatibility, auth, etc.
  # 3. Re-validation (declarative) - ensures processing didn't break schema
  class Config
    using IndifferentHashAccess

    @xdg = XDG::Environment.new

    # This lets local project settings override user settings, which
    # override system defaults. It's the standard precedence.
    #
    @paths = [
      File.join(Dir.pwd, 'etc'), # 1. current working directory
      File.join(Onetime::HOME, 'etc'), # 2. onetimesecret/etc
      File.join(@xdg.config_home, 'onetime'), # 3. ~/.config/onetime
      File.join(File::SEPARATOR, 'etc', 'onetime'), # 4. /etc/onetime
    ]
    @extensions = ['.yml', '.yaml', '.json', '.json5', '']

    attr_accessor :config_path, :schema_path
    attr_reader :configuration, :schema

    def initialize(config_path: nil, schema_path: nil)
      @config_path = config_path || self.class.find_config('config')
      @schema_path = schema_path || self.class.find_config('config.schema')
    end

    # States:
    attr_reader :unprocessed_config, :validated_config, :schema, :parsed_template
    attr_reader :rendered_yaml, :config_template_str, :processed_config

    def load!
      normalize_environment

      @schema = load_schema
      @configuration = config_path
        .then { |path| read_template_file(path) }
        # We validate before returning the config so that we're not inadvertently
        # sending back configuration of unknown provenance. This is Stage 1 of
        # our two-stage validation process. In addition to confirming the
        # correctness, this validation also applies default values.
        .then { |template| render_erb_template(template) }
        .then { |yaml_content| parse_yaml(yaml_content) }
        .then { |config| validate_with_defaults(config) }
        .then { |config| after_load(config) }
        .then { |config| validate(config) }
        .then { |config| deep_freeze(config) }

      self
    rescue OT::ConfigError => e
      log_debug_content(e)
      raise
    rescue StandardError => e
      log_debug_content(e)
      raise OT::ConfigError, "Configuration loading failed: #{e.message}"
    end

    def read_template_file(path)
      OT.ld("[Config] Reading template file: #{path}")
      @template_str = OT::Config::Load.file_read(path)
    end

    def render_erb_template(template)
      OT.ld("[Config] Rendering ERB template (#{template.size} bytes)")
      @rendered_template = ERB.new(template).result #(binding)
    end

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def parse_yaml(content)
      OT.ld("[Config] Parsing YAML content (#{content.size} bytes)")
      @rendered_yaml = OT::Config::Load.yaml_load(content)
    end

    # Configuration processing can introduce new failure modes so we validate
    # both when the config is loaded initially and after processing. This
    # allows us to fail fast with clear error messages.
    # First validation: Schema validation before processing.
    # Ensures structural integrity, applies defaults.
    def validate_with_defaults(config)
      OT.ld("[Config] Validating w/ defaults (#{config.size} sections)")
      _validate(config, apply_defaults: true)
    end

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # Operates on the loaded, unprocessed configuration hash in raw form. This
    # imperative logic deals with complex configuration processing that is
    # beyond what can reasonably be handled by declarative validation (e.g.
    # zod transformations).
    #
    # @return [Hash] The processed configuration has
    def after_load(config) = config

    def validate(config)
      OT.ld("[Config] Validating w/o defaults (#{config.size} sections)")
      _validate(config, apply_defaults: false)
    end

    def deep_freeze(config)
      OT.ld("[Config] Deep freezing (#{config.size} sections)")
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

      OT.ld "[Config] Template: #{@template_str}" if @template_str
      OT.ld "[Config] Rendered: #{@rendered_yaml}" if @rendered_yaml
      if unprocessed_config
        loggable_config = OT::Utils.type_structure(unprocessed_config)
        OT.ld "[Config] Parsed: #{loggable_config}"
      end

      OT.le err.message
      OT.ld err.backtrace.join("\n")
    end

    def load_schema(path = nil)
      path ||= schema_path
      OT.ld "[Config] Loading schema from #{path}"
      OT::Config::Load.yaml_load_file(path)
    end

    private

    def _validate(config, **)
      unless config.is_a?(Hash) && schema.is_a?(Hash)
        raise ArgumentError, "Invalid configuration format"
      end
      # loggable_config = OT::Utils.type_structure(config)
      # OT.ld "[Config] Validating #{loggable_config.size} #{schema.size}"
      OT::Config::Utils.validate_with_schema(config, schema, **)
    end

    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    def normalize_environment
      OT.ld "[Config] Normalizing environment variables"
      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      set_value = ENV.values_at('REGIONS_ENABLED', 'REGIONS_ENABLE').compact.first
      ENV['REGIONS_ENABLED'] = set_value || 'false'
    end

    class << self
      attr_reader :xdg, :paths, :extensions

      def load!
        conf = new
        conf.load!
        conf
      end

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

__END__

#
# Work over these and at the bottom of config_module.rb.txt
#

def after_load
  # # Process colonels backwards compatibility
  # process_colonels_compatibility!(local_copy)

  # # Validate critical configuration
  # check_global_secret!(local_copy)

  # # Process authentication settings
  # process_authentication_settings!(local_copy)
end

def process_colonels_compatibility!(config)
  # Ensure site.authentication exists (using string keys)
  config['site'] ||= {}
  config['site']['authentication'] ||= {}

  # Handle colonels backwards compatibility (handle both symbol and string keys)
  root_colonels = config.delete('colonels') || config.delete(:colonels)
  auth_colonels = config['site']['authentication']['colonels']

  if auth_colonels.nil?
    # No colonels in authentication, use root colonels or empty array
    config['site']['authentication']['colonels'] = root_colonels || []
  elsif root_colonels
    # Combine existing auth colonels with root colonels
    config['site']['authentication']['colonels'] = auth_colonels + root_colonels
  end
end

def check_global_secret!(config)
  site_secret = config.dig('site', 'secret')
  if site_secret.nil? || site_secret == 'CHANGEME'
    raise OT::Problem, "Global secret cannot be nil or CHANGEME"
  end
end

def process_authentication_settings!(config)
  auth_config = config.dig('site', 'authentication')
  return unless auth_config

  # If authentication is disabled, set all auth sub-features to false
  unless auth_config['enabled']
    auth_config['colonels'] = false
    auth_config['signup'] = false
    auth_config['signin'] = false
    auth_config['autoverify'] = false
  end
end

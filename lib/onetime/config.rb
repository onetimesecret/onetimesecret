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

    attr_reader :config_path, :schema_path, :local_copy, :config,
          :unprocessed_config, :validated_config, :schema, :parsed_template,
          :rendered_yaml, :config_template_str, :processed_config

    def initialize(config_path: nil, schema_path: nil)
      @config_path = config_path || self.class.find_config('config')
      @schema_path = schema_path || self.class.find_config('config.schema')
    end

    def load!
      before_load
      load
      after_load
    end

    def load
      @schema = load_schema

      # We validate before returning the config so that we're not inadvertently
      # sending back configuration of unknown provenance. This is Stage 1 of
      # our two-stage validation process. In addition to confirming the
      # correctness, this validation also applies default values.
      @unprocessed_config = load_config

    end

    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    def before_load
      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      set_value = ENV.values_at('REGIONS_ENABLED', 'REGIONS_ENABLE').compact.first
      ENV['REGIONS_ENABLED'] = set_value || 'false'
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
    def after_load

      # Create a deep copy and normalize keys to strings
      local_copy = OT::Utils.deep_merge({}, unprocessed_config)


      # Stage 2: Re-validate the processed result against the same schema
      # # Stage 2: Business logic processing + Stage 3: Re-validation.
      # Processing may violate schema constraints, so we validate the result.

      local_copy = validate_with_schema(local_copy, schema)
      @processed_config = OT::Utils.deep_freeze(local_copy)
    end

    # Configuration processing can introduce new failure modes so we validate
    # both when the config is loaded initially and after processing. This
    # allows us to fail fast with clear error messages.
    # First validation: Schema validation before processing.
    # Ensures structural integrity, applies defaults.
    def validate
      loggable_config = OT::Utils.type_structure(unprocessed_config)
      OT.ld "[Config] Validating #{loggable_config} #{schema.inspect}"
      return false unless unprocessed_config.is_a?(Hash) && schema.is_a?(Hash)
      OT::Config::Utils.validate_with_schema(unprocessed_config, schema)
    end

    private

    def load_schema(path = nil)
      path ||= @schema_path
      OT::Config::Load.yaml_load_file(path)
    rescue OT::ConfigError => e
      OT.le "Cannot load schema (#{e.message})"
      nil
    end

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def load_config(path = nil)
      path ||= @config_path

      @config_template_str = OT::Config::Load.file_read(path)
      @parsed_template = ERB.new(@config_template_str)
      @rendered_yaml = @parsed_template.result

      validate OT::Config::Load.yaml_load(@rendered_yaml)

    rescue OT::ConfigError => e
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

      OT.le e.message
      OT.ld e.backtrace.join("\n")
      raise e
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

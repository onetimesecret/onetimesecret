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
          :rendered_yaml, :config_template_str

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
      @unprocessed_config = load_config
      @validated_config = validate
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

    def validate
      OT::Config::Utils.validate_with_schema(unprocessed_config, schema)
    end

    # After loading the configuration, this method processes and validates the
    # configuration, setting defaults and ensuring required elements are present.
    # It also performs deep copy protection to prevent mutations from propagating
    # to shared configuration instances.
    #
    # Operates on the loaded, unprocessed configuration hash in raw form.
    #
    # @return [Hash] The processed configuration has
    def after_load

      # Create a deep copy of the configuration to prevent unintended mutations
      local_copy = OT::Utils.deep_clone(unprocessed_config)

      # Process colonels backwards compatibility
      process_colonels_compatibility!(local_copy)

      # Validate critical configuration
      validate_critical_config!(local_copy)

      # Process authentication settings
      process_authentication_settings!(local_copy)

      @config = OT::Utils.deep_freeze(local_copy)
    end

    private

    def process_colonels_compatibility!(config)
      # Ensure site.authentication exists
      config[:site] ||= {}
      config[:site][:authentication] ||= {}

      # Handle colonels backwards compatibility
      root_colonels = config.delete(:colonels)
      auth_colonels = config[:site][:authentication][:colonels]

      if auth_colonels.nil?
        # No colonels in authentication, use root colonels or empty array
        config[:site][:authentication][:colonels] = root_colonels || []
      elsif root_colonels
        # Combine existing auth colonels with root colonels
        config[:site][:authentication][:colonels] = auth_colonels + root_colonels
      end
    end

    def validate_critical_config!(config)
      site_secret = config.dig(:site, :secret)
      if site_secret.nil? || site_secret == 'CHANGEME'
        raise OT::Problem, "Global secret cannot be nil or CHANGEME"
      end
    end

    def process_authentication_settings!(config)
      auth_config = config.dig(:site, :authentication)
      return unless auth_config

      # If authentication is disabled, set all auth sub-features to false
      unless auth_config[:enabled]
        auth_config[:colonels] = false
        auth_config[:signup] = false
        auth_config[:signin] = false
        auth_config[:autoverify] = false
      end
    end


    def raise_concerns
    end

    def load_schema(path = @schema_path)
      OT::Config::Load.yaml_load_file(path)
    end

    # Load a YAML configuration file, allowing for ERB templating within the file.
    # This reads the file at the given path, processes any embedded Ruby (ERB) code,
    # and then parses the result as YAML.
    #
    # @param path [String] (optional the path to the YAML configuration file
    # @return [Hash] the parsed YAML data
    #
    def load_config(path = @config_path)

      @config_template_str = OT::Config::Load.file_read(path)
      @parsed_template = ERB.new(@config_template_str)
      @rendered_yaml = @parsed_template.result

      OT::Config::Load.yaml_load(@rendered_yaml)

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
